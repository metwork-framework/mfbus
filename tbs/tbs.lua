-----------------------------------
-- general variables and modules --
-----------------------------------
local http = require("resty.http")
local mfutil = require("mfutil")
local cjson = require("cjson")
local redis = require "resty.redis"
local module_runtime_home = os.getenv("MFMODULE_RUNTIME_HOME")
local default_lifetime = 3600
local default_lifetime_str = os.getenv("MFBUS_TBS_DEFAULT_LIFETIME")
if (default_lifetime_str ~= nil) then
    default_lifetime = tonumber(default_lifetime_str)
end
local max_lifetime = 3600
local max_lifetime_str = os.getenv("MFBUS_TBS_MAX_LIFETIME")
if (max_lifetime_str ~= nil) then
    max_lifetime = tonumber(max_lifetime_str)
end
local nginx_port = tonumber(os.getenv("MFSERV_NGINX_PORT"))
local max_namespace_size = 10000000000
local max_namespace_size_str = os.getenv("MFBUS_TBS_MAX_NAMESPACE_SIZE")
if (max_namespace_size_str ~= nil) then
    max_namespace_size = tonumber(max_namespace_size_str)
end
local max_namespace_size_in_bytes = 10000000000
local max_namespace_size_in_bytes_str = os.getenv("MFBUS_TBS_MAX_NAMESPACE_SIZE_IN_BYTES")
if (max_namespace_size_in_bytes_str ~= nil) then
    max_namespace_size_in_bytes = tonumber(max_namespace_size_in_bytes_str)
end

local function get_storage_path(namespace, blob_uid)
    return string.format("/%s/%s", namespace, blob_uid)
end

-- return the absolute blob url with automatic processing of X-Forwarded-*
--     headers in case of reverse proxies setup
local function get_blob_absolute_url(namespace, blob_uid)
    local proto
    local host
    local port_str = ''
    local path_str
    if ngx.var.http_x_forwarded_proto ~= nil then
        proto = ngx.var.http_x_forwarded_proto
    else
        proto = ngx.var.scheme
    end
    if ngx.var.http_x_forwarded_host ~= nil then
        host = ngx.var.http_x_forwarded_host
    else
        if ngx.var.http_host ~= nil then
            host = ngx.var.http_host
        else
            host = ngx.var.host .. ":" .. ngx.var.server_port
        end
    end
    if ngx.var.http_x_forwarded_port ~= nil then
        if ngx.var.http_x_forwarded_port ~= "80" then
            port_str = ':' .. ngx.var.http_x_forwarded_port
        end
    end
    if ngx.var.http_x_forwarded_path ~= nil then
        path_str = ngx.var.http_x_forwarded_path .. '/' .. blob_uid
    else
        path_str = '/tbs/' .. namespace .. '/blobs/' .. blob_uid
    end
    return proto .. "://" .. host .. port_str .. path_str
end

local function jsonapi_error(status, title, detail)
    ngx.status = status
    ngx.header['Content-Type'] = 'application/vnd.api+json'
    local errors = {}
    local err = {}
    err['status'] = status
    err['title'] = title
    err['detail'] = detail
    errors['errors'] = {err}
    if status >= 500 then
        ngx.log(ngx.WARN, string.format("HTTP/%i error (title: %s, detail: %s)",
                                        status, title, detail))
    end
    ngx.say(cjson.new().encode(errors))
    ngx.exit(200)
end

local function get_redis_connection()
    local r = redis:new()
    r:set_timeout(9000)
    local redis_socket_path = module_runtime_home .. "/var/redis_plugin_" .. ngx.var.tbs_plugin_name .. ".socket"
    local ok, err = r:connect("unix:" .. redis_socket_path)
    if not ok then
        jsonapi_error(500, "redis error", "can't connect")
    end
    return r
end

local function close_redis_connection(r)
    local ok, err = r:set_keepalive(10000, 10000)
    if not ok then
        jsonapi_error(500, "redis error", "can't set_keepalive")
    end
end

local function assert_valid_namespace(namespace)
    if string.len(namespace) > 64 then
        jsonapi_error(400, "bad namespace", "the namespace length must be <= 64")
    end
    if string.match(namespace, "[^%w%._%-]") then
        jsonapi_error(400, "bad namespace", "forbidden character found in namespace")
    end
end

local function assert_valid_blob_uid(namespace)
    if string.len(namespace) > 64 then
        jsonapi_error(400, "bad blob uid", "the blod_uid length must be <= 64")
    end
    if string.match(namespace, "[^%w%._%-]") then
        jsonapi_error(400, "bad blob uid", "forbidden character found in blob_uid")
    end
end

local function redis_namespace_counter_key(namespace)
    return "namespace_counter@" .. namespace
end

local function redis_namespace_counter_in_bytes_key(namespace)
    return "namespace_counter_in_bytes@" .. namespace
end

local function redis_blob_key(namespace, blob_uid)
    return string.format("blob@%s,%s", namespace, blob_uid)
end

local function get_body()
    local data = ngx.req.get_body_data()
    if data then
        return { string.len(data), data }
    end
    local filepath = ngx.req.get_body_file()
    if filepath then
        return { mfutil.get_file_size(filepath), nil }
    else
        return { -1, nil }
    end
end


local function redis_new_blob(namespace, blob_uid, blob_size, blob_storage_path, blob_lifetime, blob_content_type, blob_content_disposition, blob_data)
    local r = get_redis_connection()
    r:init_pipeline()
    local key1 = redis_namespace_counter_key(namespace)
    local key2 = redis_namespace_counter_in_bytes_key(namespace)
    local key3 = redis_blob_key(namespace, blob_uid)
    r:incr(key1)
    r:incrby(key2, blob_size)
    r:hset(key3, "lifetime", blob_lifetime)
    r:hset(key3, "expire_at", os.time() + blob_lifetime)
    r:hset(key3, "size", blob_size)
    r:hset(key3, "content_type", blob_content_type)
    r:hset(key3, "content_disposition", blob_content_disposition)
    if blob_data ~= nil then
        r:hset(key3, "data", blob_data)
    else
        r:hset(key3, "data_path", blob_storage_path)
    end
    r:zadd("expiration_zset", os.time() + blob_lifetime, key3)
    local results, err = r:commit_pipeline()
    close_redis_connection(r)
    if not results == nil then
        ngx.log(ngx.WARN, "can't commit redis pipeline")
        return nil
    end
    local new_counter
    local new_counter_in_bytes
	for i, res in ipairs(results) do
		if type(res) == "table" then
			if res[1] == false then
				ngx.log(ngx.WARN, "failed to run redis command ", i, ": ", res[2])
			end
		else
            if i == 1 then
                new_counter = res
            elseif i == 2 then
                new_counter_in_bytes = res
            end
		end
	end
    return new_counter, new_counter_in_bytes
end

local function redis_get_blob(namespace, blob_uid)
    local key3 = redis_blob_key(namespace, blob_uid)
    local r = get_redis_connection()
    local i
    local everything_is_nil = true
    local results, err = r:hmget(key3, "lifetime", "data_path", "size", "content_type", "content_disposition", "data", "expire_at")
    close_redis_connection(r)
    if not results then
        return nil
    end
    if #results ~= 7 then
        return nil
    end
    for i = 1, 7 do
      if results[i] ~= nil and results[i] ~= ngx.null then
        everything_is_nil = false
      end
    end
    if everything_is_nil then
        return nil
    end
    local t = {}
    t["lifetime"] = results[1]
    t["data_path"] = results[2]
    t["size"] = results[3]
    t["content_type"] = results[4]
    t["content_disposition"] = results[5]
    t["data"] = results[6]
    t["expire_at"] = results[7]
    return t
end

local function redis_delete_blob(namespace, blob_uid, blob_size)
    local r = get_redis_connection()
    local key1 = redis_namespace_counter_key(namespace)
    local key2 = redis_namespace_counter_in_bytes_key(namespace)
    local key3 = redis_blob_key(namespace, blob_uid)
    if blob_size == nil then
        local blob = redis_get_blob(namespace, blob_uid)
        if blob == nil then
            return nil
        end
        blob_size = blob["size"]
    end
    r:init_pipeline()
    r:decr(key1)
    r:decrby(key2, blob_size)
    r:del(key3)
    r:zrem("expiration_zset", key3)
    r:commit_pipeline()
    close_redis_connection(r)
end

local tmp_blob_server = {}

function tmp_blob_server.new_blob(namespace)
    -- FIXME: global limit
    assert_valid_namespace(namespace)
    local blob_uid = mfutil.get_unique_hexa_identifier()
    local content_type = ngx.var.http_x_tmpblobstore_contenttype
    if content_type == nil then
        content_type = "application/octet-stream"
    end
    local content_disposition = ngx.var.http_x_tmpblobstore_contentdisposition
    if content_disposition == nil then
        content_disposition = "null"
    end
    local lifetime_string = ngx.var.http_x_tmpblobstore_lifetime
    local lifetime = default_lifetime
    if lifetime_string ~= nil then
        lifetime = tonumber(lifetime_string)
    end
    if lifetime > max_lifetime then
        jsonapi_error(400, "lifetime", "lifetime must be <= " .. max_lifetime)
    end
    ngx.req.read_body()
    local tmp = get_body()
    local blob_size = tmp[1]
    local blob_data_or_nil = tmp[2]
    if blob_size < 0 then
        jsonapi_error(400, "body", "can't read body size")
    end
    local blob_storage_path = get_storage_path(namespace, blob_uid)
    local new_counter, new_counter_in_bytes = redis_new_blob(namespace, blob_uid, blob_size, blob_storage_path, lifetime, content_type, content_disposition, blob_data_or_nil)
    if new_counter == nil then
        jsonapi_error(500, "redis", "can't register blob into redis")
    end
    if max_namespace_size >= 0 then
        if new_counter > max_namespace_size then
            redis_delete_blob(namespace, blob_uid, blob_size)
            jsonapi_error(429, "limit", "too many blobs for this namespace")
        end
    end
    if max_namespace_size_in_bytes >= 0 then
        if new_counter_in_bytes > max_namespace_size_in_bytes then
            jsonapi_error(429, "limit", "too many blob bytes for this namespace")
        end
    end
    if blob_data_or_nil == nil then
        local upload_uri = string.format("/__tbs_upload%s", blob_storage_path)
        local res = ngx.location.capture(upload_uri, { method = ngx.HTTP_PUT})
        if res.status ~= 201 then
            redis_delete_blob(namespace, blob_uid, blob_size)
            jsonapi_error(500, "storage error", "can't store the blob with status" .. res.status .. " and body " .. res.body)
        end
    end
    local blob_uri = get_blob_absolute_url(namespace, blob_uid)
    ngx.status = 201
    ngx.header["Location"] = blob_uri
    ngx.header["Content-Type"] = 'application/vnd.api+json'
    local reply = {}
    reply['data'] = {}
    reply['data']['type'] = 'blob'
    reply['data']['id'] = blob_uid
    reply['data']['links'] = {}
    reply['data']['links']['self'] = blob_uri
    reply['data']['attributes'] = {}
    reply['data']['attributes']['lifetime'] = lifetime
    reply['data']['attributes']['content-type'] = content_type
    reply['data']['attributes']['content-disposition'] = content_disposition
    ngx.say(cjson.encode(reply))
end

function tmp_blob_server.get_blob(namespace, blob_uid)
    assert_valid_namespace(namespace)
    assert_valid_blob_uid(blob_uid)
    local blob = redis_get_blob(namespace, blob_uid)
    if blob == nil then
        ngx.status = 404
        ngx.exit(200)
    end
    ngx.header["Content-Type"] = blob['content_type']
    if blob['content_disposition'] ~= 'null' then
        ngx.header["Content-Disposition"] = blob['content_disposition']
    end
    if ngx.var.arg_delete == "1" then
        ngx.ctx.delete_after_get = 1
    end
    if blob["data"] ~= ngx.null then
        ngx.print(blob["data"])
    else
        return ngx.exec("/__tbs_download" .. blob['data_path'])
    end
end

function tmp_blob_server.delete_blob(namespace, blob_uid)
    assert_valid_namespace(namespace)
    assert_valid_blob_uid(blob_uid)
    local blob = redis_get_blob(namespace, blob_uid)
    if blob == nil then
        ngx.status = 404
        ngx.exit(200)
    end
    redis_delete_blob(namespace, blob_uid, nil)
    if blob['data_path'] ~= ngx.null then
        return ngx.exec(string.format("/__tbs_delete%s", blob['data_path']))
    else
        ngx.status = 204
        ngx.exit(200)
    end
end

local function __delete(premature, namespace, blob_uid)
    local uri = string.format("/tbs/%s/blobs/%s", namespace, blob_uid)
    local httpc = http.new()
    httpc:set_timeout(60000)
    httpc:connect("127.0.0.1", nginx_port)
    httpc:request({method = "DELETE", path=uri})
    httpc:set_keepalive(10, 100)
end

function tmp_blob_server.after_get(namespace, blob_uid)
    if ngx.ctx.delete_after_get == 1 then
        -- to circumvent limitatons of log_by_lua (no cosocket api)
        local ok, err = ngx.timer.at(0, __delete, namespace, blob_uid)
        if not ok then
            jsonapi_error(500, "can't delete blob", "failed to create timer")
        end
    end
end

return tmp_blob_server
