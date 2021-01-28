#!/bin/bash

set -eu


    
    


    
        
    

cd /src
mkdir -p "/opt/metwork-${MFMODULE_LOWERCASE}-${TARGET_DIR}"

./bootstrap.sh /opt/metwork-{{FORCED_REPO}}-${TARGET_DIR} /opt/metwork-{{DEP_MODULE}}-${DEP_DIR}

cat adm/root.mk
env | sort
