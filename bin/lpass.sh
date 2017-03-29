#!/bin/bash

# security through obscurity
umask 0066

username=${LPASS_USER}
bdir=${LPASS_BDIR}

[ -z "$username" ] && echo "LPASS_USER env var not set" && exit 1
[ -z "$bdir" ] && echo "LPASS_BDIR env var not set" && exit 1

lpass login $username
[ $? -ne 0 ] && echo "Failed to login user [$username]" && exit 1

mkdir -p "$bdir"
[ $? -ne 0 ] && echo "Failed to create backup directory $bdir" && exit 1

cd $bdir/
echo "Backup to $bdir/lastpass.$(date +%Y%m%d).csv.gpg"
lpass export --sync=now | gpg -e -o lastpass.$(date +%Y%m%d).csv.gpg
lpass logout -f

