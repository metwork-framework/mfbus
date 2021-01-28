#!/bin/bash

set -eu


    
    


    
        
    

cd /src
mkdir -p "/opt/metwork-${MFMODULE_LOWERCASE}-${TARGET_DIR}"

./bootstrap.sh /opt/metwork-mfbus-${TARGET_DIR} /opt/metwork-mfext-${DEP_DIR}

cat adm/root.mk
env | sort
