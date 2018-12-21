#!/bin/bash

set -eu

MAX_LIFETIME_IN_MINUTES=$(expr "${MFBUS_TMP_BLOB_STORE_MAX_LIFETIME}" / 60)
DOUBLE_MAX_LIFETIME_IN_MINUTES=$(expr 2 \* "${MAX_LIFETIME_IN_MINUTES}")

# nginx tmp cleaning
find "${MFBUS_NGINX_CLIENTBODY_TEMP_PATH}" -type f -follow -mmin +360 -delete >/dev/null 2>&1
find "${MFBUS_NGINX_PROXY_TEMP_PATH}" -type f -follow -mmin +360 -delete >/dev/null 2>&1

# tmp blob store cleaning
find "${MFBUS_TMP_BLOB_STORE_STORAGE_DIR}" -type f -follow -mmin +"${DOUBLE_MAX_LIFETIME_IN_MINUTES}" -delete >/dev/null 2>&1
find "${MFBUS_TMP_BLOB_STORE_STORAGE_DIR}" -mindepth 1 -type d -follow -exec rmdir {} \; >/dev/null 2>&1
tmp_blob_store_clean.py
