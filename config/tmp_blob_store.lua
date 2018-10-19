local synutil = require("synutil")
local cjson = require("cjson")
local redis = require "resty.redis"
local module_runtime_home = os.getenv("MODULE_RUNTIME_HOME")
local default_lifetime = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_DEFAULT_LIFETIME"))
local max_lifetime = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_MAX_LIFETIME"))
local max_namespace_size = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_MAX_NAMESPACE_SIZE"))
local max_namespace_size_in_bytes = tonumber(os.getenv("MFBUS_TMP_BLOB_STORE_MAX_NAMESPACE_SIZE_IN_BYTES"))

-- see http://lua-users.org/wiki/TableUtils
function table.val_to_str ( v )
	if "string" == type( v ) then
	v = string.gsub( v, "\n", "\\n" )
	if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
		return "'" .. v .. "'"
	end
	return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
	else
	return "table" == type( v ) and table.tostring( v ) or
		tostring( v )
	end
end

function table.key_to_str ( k )
	if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
	return k
	else
	return "[" .. table.val_to_str( k ) .. "]"
	end
end

function table.tostring( tbl )
	local result, done = {}, {}
	for k, v in ipairs( tbl ) do
	table.insert( result, table.val_to_str( v ) )
	done[ k ] = true
	end
	for k, v in pairs( tbl ) do
	if not done[ k ] then
		table.insert( result,
		table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
	end
	end
	return "{" .. table.concat( result, "," ) .. "}"
end

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
    r = redis:new()
    r:set_timeout(9000)
    local ok, err = r:connect("unix:" .. module_runtime_home .. "/var/redis.socket")
    if not ok then
        jsonapi_error(500, "redis error", "can't connect")
    end
    return r
end

local function close_redis_connection()
    local ok, err = red:set_keepalive(10000, 10000)
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
    return "namespace_counter_" .. namespace
end

local function redis_namespace_counter_in_bytes_key(namespace)
    return "namespace_counter_in_bytes_" .. namespace
end

local function redis_blob_key(namespace, blob_uid)
    return string.format("blob_%s_%s", namespace, blob_uid)
end

local function get_body_size()
    local filepath = ngx.req.get_body_file()
    return synutil.get_file_size(filepath)
end

local function get_storage_path(namespace, blob_uid)
    return string.format("/%s/%s", namespace, blob_uid)
end

local function redis_register_new_blob(namespace, blob_uid, blob_size, blob_storage_path, blob_lifetime, blob_content_type)
    local r = get_redis_connection()
    r:init_pipeline()
    local key1 = redis_namespace_counter_key(namespace)
    local key2 = redis_namespace_counter_in_bytes_key(namespace)
    local key3 = redis_blob_key(namespace, blob_uid)
    r:incr(key1)
    r:incrby(key2, blob_size)
    r:hset(key3, "lifetime", blob_lifetime)
    r:hset(key3, "path", blob_storage_path)
    r:hset(key3, "size", blob_size)
    r:hset(key3, "content_type", blob_content_type)
    results, err = r:commit_pipeline()
    close_redis_connection(r)
    if results == nil then
        ngx.log(ngx.WARN, "coucou")
        return nil
    end
    local new_counter = results[0]
    local new_counter_in_bytes = results[1]
    return { new_counter, new_counter_in_bytes }
end

local function redis_get_storage_path(namespace, blob_uid)
    local key3 = redis_blob_key(namespace, blob_uid)
    local r = get_redis_connection()
    local result, err = r:hget(key3, "storage_path")
    close_redis_connection(r)
    return result
end

local function redis_get_content_type_and_storage_path(namespace, blob_uid)
    local key3 = redis_blob_key(namespace, blob_uid)
    local r = get_redis_connection()
    local result1, err1 = r:hget(key3, "content_type")
    local result2, err2 = r:hget(key3, "storage_path")
    close_redis_connection(r)
    return { result1, result2 }
end

local function redis_get_size(namespace, blob_uid)
    local key3 = redis_blob_key(namespace, blob_uid)
    local r = get_redis_connection()
    local result, err = r:hget(key3, "size")
    close_redis_connection(r)
    if result ~= nil then
        return tonumber(result)
    else
        return nil
    end
end

local function redis_unregister_blob(namespace, blob_uid, blob_size)
    local r = get_redis_connection()
    local key1 = redis_namespace_counter_key(namespace)
    local key2 = redis_namespace_counter_in_bytes_key(namespace)
    local key3 = redis_blob_key(namespace, blob_uid)
    if blob_size == nil then
        blob_size = redis_get_size(namespace, blob_uid)
        if blob_size == nil then
            return nil
        end
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
    -- FIXME: test max_lifetime
    ngx.req.read_body()
    local blob_size = get_body_size()
    if blob_size < 0 then
        jsonapi_error(400, "body", "can't read body size")
    end
    local storage_path = get_storage_path(namespace, blob_uid)
    local new_counter, new_counter_in_bytes = redis_register_new_blob(r, namespace, blob_uid, blob_size, blob_storage_path, lifetime, content_type)
    if new_counter ~= nil then
        jsonapi_error(500, "redis", "can't register blob into redis")
    end
    if max_namespace_size >= 0 then
        if new_counter > max_namespace_size then
            redis_unregister_blob(namespace, blob_uid, blob_size)
            jsonapi_error(429, "limit", "too many blobs for this namespace")
        end
    end
    if max_namespace_size_in_bytes >= 0 then
        if new_counter_in_bytes > max_namespace_size_in_bytes then
            jsonapi_error(429, "limit", "too many blob bytes for this namespace")
        end
    end
    local upload_uri = "/__upload" .. storage_path
    local res = ngx.location.capture(upload_uri, { method = ngx.HTTP_PUT})
    if res.status ~= 201 then
        redis_unregister_blob(namespace, blob_uid, blob_size)
        jsonapi_error(500, "storage error", "can't store the blob")
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
    local content_type, storage_path = redis_get_content_type_and_storage_path(namespace, blob_uid)
    if content_type == nil or storage_path == nil then
        ngx.status = 404
        ngx.exit(200)
    end
    ngx.header["Content-Type"] = content_type
    return ngx.exec("/__download" .. storage_path)
end

function tmp_blob_server.delete_blob(namespace, blob_uid)
    assert_valid_namespace(namespace)
    assert_valid_blob_uid(blob_uid)
    local content_type, storage_path = redis_get_content_type_and_storage_path(namespace, blob_uid)
    if content_type == nil or storage_path == nil then
        ngx.status = 404
        ngx.exit(200)
    end
    redis_unregister_blob(namespace, blob_uid, nil)
    return ngx.exec("/__delete/" .. storage_path)
end

return tmp_blob_server
