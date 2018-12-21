local synutil = require("synutil")
local cjson = require("cjson")
local redis = require "resty.redis"
local module_runtime_home = os.getenv("MODULE_RUNTIME_HOME")
local default_lifetime = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_DEFAULT_LIFETIME"))
local max_lifetime = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_MAX_LIFETIME"))
local max_namespace_size = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_MAX_NAMESPACE_SIZE"))
local max_namespace_size_in_bytes = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_MAX_NAMESPACE_SIZE_IN_BYTES"))

local function get_absolute_url_root()
    local proto
    local host
    if ngx.header.x_forwarded_proto ~= nil then
        proto = ngx.header.x_forwarded_proto
    else
        proto = ngx.var.scheme
    end
    if ngx.header.x_forwarded_host ~= nil then
        host = ngx.header.x_forwarded_host
    else
        if ngx.var.http_host ~= nil then
            host = ngx.var.http_host
        else
            host = ngx.var.host .. ":" .. ngx.var.server_port
        end
    end
    return proto .. "://" .. host
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
    local ok, err = r:connect("unix:" .. module_runtime_home .. "/var/redis.socket")
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
        return { synutil.get_file_size(filepath), nil }
    else
        return { -1, nil }
    end
end

local function get_storage_path(namespace, blob_uid)
    return string.format("/%s/%s", namespace, blob_uid)
end

local function redis_new_blob(namespace, blob_uid, blob_size, blob_storage_path, blob_lifetime, blob_content_type, blob_data)
    local r = get_redis_connection()
    r:init_pipeline()
    local key1 = redis_namespace_counter_key(namespace)
    local key2 = redis_namespace_counter_in_bytes_key(namespace)
    local key3 = redis_blob_key(namespace, blob_uid)
    r:incr(key1)
    r:incrby(key2, blob_size)
    r:hset(key3, "lifetime", blob_lifetime)
    r:hset(key3, "expire_at", synutil.time() + blob_lifetime)
    r:hset(key3, "size", blob_size)
    r:hset(key3, "content_type", blob_content_type)
    if blob_data ~= nil then
        r:hset(key3, "data", blob_data)
    else
        r:hset(key3, "data_path", blob_storage_path)
    end
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
    return { new_counter, new_counter_in_bytes }
end

local function redis_get_blob(namespace, blob_uid)
    local key3 = redis_blob_key(namespace, blob_uid)
    local r = get_redis_connection()
    local results, err = r:hmget(key3, "lifetime", "data_path", "size", "content_type", "data", "expire_at")
    close_redis_connection(r)
    if not results then
        return nil
    end
    if #results ~= 6 then
        return nil
    end
    local t = {}
    t["lifetime"] = results[1]
    t["data_path"] = results[2]
    t["size"] = results[3]
    t["content_type"] = results[4]
    t["data"] = results[5]
    t["expire_at"] = results[6]
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
    r:commit_pipeline()
    close_redis_connection(r)
end

local tmp_blob_server = {}

function tmp_blob_server.new_blob(namespace)
    -- FIXME: global limit
    assert_valid_namespace(namespace)
    local blob_uid = synutil.get_unique_hexa_identifier()
    local content_type = ngx.header.x_tmpblobstore_contenttype
    if content_type == nil then
        content_type = "application/octet-stream"
    end
    local lifetime_string = ngx.header.x_tmpblobstore_lifetime
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
    local blob_storage_path = nil
    if blob_data_or_nil == nil then
        blob_storage_path = get_storage_path(namespace, blob_uid)
    end
    local new_counter, new_counter_in_bytes = redis_new_blob(namespace, blob_uid, blob_size, blob_storage_path, lifetime, content_type, blob_data_or_nil)
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
        local upload_uri = string.format("/__upload%s", blob_storage_path)
        local res = ngx.location.capture(upload_uri, { method = ngx.HTTP_PUT})
        if res.status ~= 201 then
            redis_delete_blob(namespace, blob_uid, blob_size)
            jsonapi_error(500, "storage error", "can't store the blob with status" .. res.status .. " and body " .. res.body)
        end
    end
    local blob_uri = get_absolute_url_root() .. ngx.var.request_uri .. "/" .. blob_uid
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
    if blob["data"] ~= ngx.null then
        ngx.print(blob["data"])
    else
        return ngx.exec("/__download" .. blob['data_path'])
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
        return ngx.exec(string.format("/__delete%s", blob['data_path']))
    else
        ngx.status = 204
        ngx.exit(200)
    end
end

return tmp_blob_server
