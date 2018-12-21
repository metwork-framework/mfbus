#!/usr/bin/env python3

import redis
import requests
import time
import argparse
import os
from mflog import getLogger
from mfutil import get_utc_unix_timestamp

MODULE_RUNTIME_HOME = os.environ['MODULE_RUNTIME_HOME']
ROOT_URL = "http://127.0.0.1:%i/tmp_blob_store" % \
    int(os.environ['MFBUS_NGINX_PORT'])
REDIS_SOCKET_PATH = "%s/var/redis.socket" % MODULE_RUNTIME_HOME
LOGGER = getLogger("tmp_blob_store_clean")

arg_parser = argparse.ArgumentParser(description="clean tmp blob store")
arg_parser.add_argument("--iterations", type=int, default=100,
                        help="number of iterations")
arg_parser.add_argument("--wait", type=int, default=5,
                        help="wait (in seconds) before each iteration")
args = arg_parser.parse_args()

iteration = 1
while iteration <= args.iterations:
    r = redis.Redis(unix_socket_path=REDIS_SOCKET_PATH)
    utc_ts = get_utc_unix_timestamp()
    with requests.Session() as s:
        for key in r.scan_iter("blob@*"):
            expire_at = r.hget(key, "expire_at")
            if expire_at and int(expire_at) <= utc_ts:
                try:
                    tmp = key.decode().split('@')[1]
                    namespace = tmp.split(',')[0]
                    uid = tmp.split(',')[1]
                except Exception:
                    LOGGER.warn("bad redis key naming scheme: %s" %
                                key.decode())
                    continue
                LOGGER.info("blob %s/%s expired => removing it..." %
                            (namespace, uid))
                url = "%s/%s/blobs/%s" % (ROOT_URL, namespace, uid)
                reply = s.delete(url)
                if reply.status_code != 204:
                    LOGGER.warning("bad status code [%i] for DELETE %s" %
                                   (reply.status_code, url))
    for key in r.scan_iter("namespace_counter*"):
        pass
    if iteration < args.iterations:
        time.sleep(args.wait)
    iteration = iteration + 1
