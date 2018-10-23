import requests
import pytest
import os
import redis
import glob

ROOT = "http://127.0.0.1:%i/tmp_blob_store" % \
    int(os.environ['MFBUS_NGINX_PORT'])
MODULE_RUNTIME_HOME = os.environ['MODULE_RUNTIME_HOME']
TMP_BLOB_STORE_STORAGE_DIR = os.environ['MFBUS_TMP_BLOB_STORE_STORAGE_DIR']
REDIS_SOCKET_PATH = "%s/var/redis.socket" % MODULE_RUNTIME_HOME


@pytest.fixture(scope="session", autouse=True)
def session_fixture(request):
    def session_stop():
        r = redis.Redis(unix_socket_path=REDIS_SOCKET_PATH)
        keys = r.keys()
        for key in keys:
            if key.startswith("namespace_counter".encode()):
                if r.get(key) != b"0":
                    raise Exception("counter %s != 0 [%s]" % (key, r.get(key)))
            else:
                raise Exception("not cleaned redis key: %s" % key)
        for f in glob.glob("%s/**/*" % TMP_BLOB_STORE_STORAGE_DIR,
                           recursive=True):
            if os.path.isfile(f):
                raise Exception("there are some files in %s" %
                                TMP_BLOB_STORE_STORAGE_DIR)
    r = redis.Redis(unix_socket_path=REDIS_SOCKET_PATH)
    r.flushall()
    os.system("rm -Rf %s" % TMP_BLOB_STORE_STORAGE_DIR)
    request.addfinalizer(session_stop)


def upload(namespace, content):
    url = "%s/%s/blobs" % (ROOT, namespace)
    result = requests.post(url, data=content)
    return result


def delete(namespace, blob_uid):
    url = "%s/%s/blobs/%s" % (ROOT, namespace, blob_uid)
    result = requests.delete(url)
    return result


def get(namespace, blob_uid):
    url = "%s/%s/blobs/%s" % (ROOT, namespace, blob_uid)
    result = requests.get(url)
    return result


def upload_and_test(namespace, content):
    result = upload(namespace, content)
    assert result.status_code == 201
    assert result.headers['Location'].startswith(ROOT)
    j = result.json()['data']
    assert j['links']['self'] == result.headers['Location']
    uid = j['id']
    assert len(uid) >= 32
    return uid


def delete_and_test(namespace, blob_uid):
    result = delete(namespace, blob_uid)
    assert result.status_code == 204


def get_and_test(namespace, blob_uid, content_type=None, body=None):
    result = get(namespace, blob_uid)
    assert result.status_code == 200
    if content_type:
        assert result.headers['Content-Type'] == content_type
    if body:
        assert result.content == body


def test_big_upload():
    body = b"1" * 30000
    uid = upload_and_test("goodns", body)
    get_and_test("goodns", uid, "application/octet-stream", body)
    delete_and_test("goodns", uid)


def test_little_upload():
    body = b"1"
    uid = upload_and_test("goodns", body)
    get_and_test("goodns", uid, "application/octet-stream", body)
    delete_and_test("goodns", uid)
