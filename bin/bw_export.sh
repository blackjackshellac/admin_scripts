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

info "Working in $BDIR"

email=${BW_EMAIL:-$1}
bw login --check
if [ $? -ne 0 ]; then
	unset BW_SESSION
	info bw login $email
	bw login $email | grep 'export BW_SESSION=' | cut -d'$' -f2 > bw_session
	declare -i res=${PIPESTATUS[0]}
	[ $res -ne 0 ] && die "Failed to authenticate as username $email"
	cat bw_session
	source bw_session
	[ -z "$BW_SESSION" ] && die "No BW_SESSION found"
	echo $BW_SESSION
fi

now=$(date +%Y%m%d_%H%M%S)
out=$(pwd)/${ME}_${now}.json.gpg
info bw export --raw --format json
bw export --raw --format json | gpg -e -o "$out"
declare -i gpg_res=$?
declare -i bw_res=${PIPESTATUS[0]}
[ $bw_res -ne 0 ] && die "Failed to export output to $out"
[ $gpg_res -ne 0 ] && die "Failed to gpg encrypt bw output to $out"

bw logout
[ $? -ne 0 ] && die "Failed to logout"

info "backup to $out successful"
