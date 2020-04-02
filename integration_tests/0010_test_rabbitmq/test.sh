#!/bin/bash
./send.py
./receive.py | grep Received > output_received
cat output_received
diff output_expected output_received
if test $? -ne 0; then
    exit 1
else
    exit 0
fi
