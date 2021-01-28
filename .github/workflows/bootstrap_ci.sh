#!/bin/bash

#set -eu
set -x


    

cd /src

mkdir -p /opt/metwork-${MFMODULE_LOWERCASE}-${TARGET_DIR}
./bootstrap.sh /opt/metwork-mfbus-${TARGET_DIR} /opt/metwork-mfext-${DEP_DIR}

cat adm/root.mk
env | sort
