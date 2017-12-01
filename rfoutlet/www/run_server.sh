#!/bin/bash

ME=$(basename $0 .sh)
MD=$(cd $(dirname $0); pwd)
LOG=/var/tmp/rfoutlet_server.$(date +%Y%m%d).log

cd $MD
echo Logging to $LOG
nohup ./rfoutlet_server.rb >> $LOG 2>&1 &

