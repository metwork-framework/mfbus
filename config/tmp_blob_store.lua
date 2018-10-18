local synutil = require("synutil")
local cjson = require("cjson")
local redis = require "resty.redis"

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
    ngx.say(cjson.new().encode(errors))
    ngx.exit(200)
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

local tmp_blob_server = {}

function tmp_blob_server.new_blob(namespace)
    assert_valid_namespace(namespace)
    local blob_uid = synutil.get_unique_hexa_identifier()
    local content_type = ngx.header.x_tmpblobstore_contenttype
    if content_type == nil then
        content_type = "application/octet-stream"
    end
    local lifetime_string = ngx.header.x_tmpblobstore_lifetime
    local lifetime = 3600
    if lifetime_string ~= nil then
        lifetime = tonumber(lifetime_string)
    end
    ngx.req.read_body()
    local upload_uri = "/__upload/" .. namespace .. "/" .. blob_uid
    local res = ngx.location.capture(upload_uri, { method = ngx.HTTP_PUT})
    if res.status ~= 201 then
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
    ngx.header["Content-Type"] = "application/foo"
    return ngx.exec("/__download/" .. namespace .. "/" .. blob_uid)
end

function tmp_blob_server.delete_blob(namespace, blob_uid)
    assert_valid_namespace(namespace)
    assert_valid_blob_uid(blob_uid)
    return ngx.exec("/__delete/" .. namespace .. "/" .. blob_uid)
end

return tmp_blob_server
