#!/bin/bash

ME=$(basename $0 .sh)
MD=$(dirname $0)
MESH=$(basename $0)

BDIR=~/Downloads/bw/backups/

umask 0077

puts() {
	echo -e $*
}

log() {
	puts $*
}

info() {
	log "INFO: $*"
}

warn() {
	log "WARN: $*"
}

err() {
	log "ERROR: $*"
}

die() {
	log "FATAL: $*"
	exit 1
}

email=${BW_EMAIL:-$1}

mkdir -p $BDIR
cd $BDIR
[ $? -ne 0 ] && die "Failed to change to backups dir: $BDIR"

info "Working in $BDIR"

bw_session="$(pwd)/bw_session"
if [ -z "$BW_SESSION" -a -f ${bw_session} ]; then
	source ${bw_session}
	info "BW_SESSION=$BW_SESSION"
fi

declare -i auth=1
bw login --check
if [ $? -eq 0 ]; then
	bw unlock --check
	if [ $? -eq 0 ]; then
		auth=0
	else
		auth=2
	fi
else
	auth=1
fi

if [ $auth -eq 1 ]; then
	info bw login $email
	bw login $email > bw_output
elif [ $auth -eq 2 ]; then
	info bw unlock
	bw unlock > bw_output
else
	rm -f bw_output
fi

if [ -f bw_output ]; then
	unset BW_SESSION
	info cat $(pwd)/bw_output
	cat bw_output | grep 'export BW_SESSION=' | cut -d'$' -f2 > ${bw_session}
	declare -i res=${PIPESTATUS[0]}
	[ $res -ne 0 ] && die "Failed to authenticate as username $email"
fi

if [ -z "$BW_SESSION" -a -f ${bw_session} ]; then
	info "source ${bw_session}"
	source ${bw_session}
	[ -z "$BW_SESSION" ] && die "BW_SESSION not found"
	cat ${bw_session}
fi

now=$(date +%Y%m%d_%H%M%S)
out=$(pwd)/${ME}_${now}.json.gpg
#info bw export --raw --format json
info "Read vault"
data=$(bw export --raw --format json)
[ $? -ne 0 ] && die "Failed to export vault"
[ -z "$data" ] && die "Export data is empty"

info "Encrypt to $out"
echo -ne "$data" | gpg -e -o "$out"
[ $? -ne 0 ] && die "Failed to gpg encrypt bw vault to $out"

unset data

#bw logout
#[ $? -ne 0 ] && die "Failed to logout"

puts
info "backup to $out successful"
puts
warn "Session is still unlocked"
puts "\nTo lock: bw lock"
puts "To logout: bw logout\n"
puts "BW_SESSION=""${BW_SESSION}"""
puts "source ${bw_session}"
