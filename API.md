# mfbus API

## Temporary [blob](https://en.wikipedia.org/wiki/Binary_large_object) server

mfbus module contains a "Temporary [blob](https://en.wikipedia.org/wiki/Binary_large_object) server".

With this service, you can store et retrieve various files of any type through a REST api. It's not
a storage service because all objects have a lifetime and could be automatically cleaned.

### Concepts

#### namespace

A `namespace` is just a kind of bucket for yours blobs. It's a plain string (length < 64 characters).
Allowed characters are alphanumeric ones `[0-9a-zA-Z]`, `.` (dot), `_` (underscore) and '-' (hyphen).

#### blob

You can see `blob` as a binary file. It can be a text file, an image or anything else. The service
does not make any assumptions about the content of your blobs. They are never altered.

When you submit your blob to the service, you will get a blob unique id (`blob_uid`). You have to
known your `blob_uid` to retrieve it. There is no other way (no search service...).

You can provide an indicative (media type)[https://en.wikipedia.org/wiki/Media_type] to your blob. It
will be returned as a `HTTP Content-Type header` during retrieval.

#### lifetime

All blobs have a lifetime (in seconds). The lifetime can be specific to each blob event there is a
default and a maximum value in global configuration.

### API

### POST `/tmp_blob_store/{namespace}/blobs`

This service add a new blob in the blob store inside the given `namespace`.
The blob is the (raw) body of your POST request.

Note: The `namespace` is created automatically.

If the operation is successful, the service will respond with a `HTTP/201 Created` status code
and you will get your `blob_uid` in the JSON reply (or in `Location` header).

```
HTTP/1.1 201 Created
Location: http://{...}/tmp_blob_store/{namespace}/blobs/{blob_uid}
Content-Type: application/vnd.api+json

{
    "data": {
        "type": "blob",
        "id": "{blob_uid}",
        "attributes": {
            "lifetime": 3600,
            "content-type": "application/octet-stream"
        },
        "links": {
            "self": "http://{...}/tmp/blob_store/{namespace}/blobs/{blob_uid}
        }
    }
}
```

If the operation is not successful, the service will respond with a:

- `HTTP/413`: when your blob is too large (there is a max size in the global configuration)
- `HTTP/429`: when you hit the number or the size limit of the namespace
- `HTTP/400`: in other client error cases (bad `namespace` string for example, too big lifetime...)

You can also set:

- a specific lifetime for your blob by adding (for example) a `X-TmpBlobStore-Lifetime: 60` header
to your request
- a specific indicative `Content-Type` for your blob by adding (for example) a `X-TmpBlobStore-ContentType: image/png` header

### GET `/tmp_blob_store/{namespace}/blobs/{blob_uid}[?delete=1]`

FIXME

### DELETE `/tmp_blob_store/{namespace}/blobs/{blob_uid}[?delete=1]`

FIXME
