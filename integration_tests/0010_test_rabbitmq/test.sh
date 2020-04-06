#!/bin/bash
./send.py
./receive.py | grep Received > output_received
cat output_received
diff output_expected output_received
if test $? -ne 0; then
    rm output_received
    exit 1
else
    rm output_received
    exit 0
fi
