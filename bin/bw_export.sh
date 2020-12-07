#!/bin/bash

ME=$(basename $0 .sh)
MD=$(dirname $0)
MESH=$(basename $0)

BDIR=~/Downloads/bw/backups/

umask 0077

log() {
	echo -e $*
}

info() {
	log "INFO: $*"
}

err() {
	log "ERROR: $*"
}

die() {
	log "FATAL: $*"
	exit 1
}

mkdir -p $BDIR
cd $BDIR
[ $? -ne 0 ] && die "Failed to change to backups dir: $BDIR"

bw login --check
if [ $? -ne 0 ]; then
	info bw login $1
	bw login $1 | grep 'export BW_SESSION=' | cut -d'$' -f2 > bw_session
	[ $? -ne 0 ] && die "Failed to authenticate as username $1"
	source bw_session
	echo $BW_SESSION
	cat bw_session
fi

now=$(date +%Y%m%d_%H%M%S)
out=${ME}_${now}.json.gpg
info bw export --raw --format json
bw export --raw --format json | gpg -e -o "$out"
[ $? -ne 0 ] && die "Failed to backup and encrypt output to $out"

bw logout
bw logout

info "backup to $out successful"
