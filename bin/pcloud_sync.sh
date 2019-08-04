#!/bin/bash

ME="$(basename $0 .sh)"
MD="$(cd $(dirname $0); pwd)"
TMP="/var/tmp/$ME"
NOW="$(date +%Y%m%d_%H%M)"
RSOPTS="-v -rptgo"

source $MD/funcs.sh

mkdir -p $TMP
[ $? -ne 0 ] && die "Failed to create tmp dir $TMP"

let REVERSE=0
let FULL=0
DELETE=""
SRC=/data/household/
DST=~/pCloudDrive/Crypto\ Folder

usage() {
	cat - << HELP

	$ME.sh [options]

   -s SRC - backup source directory ($SRC)
   -d DST - backup destination directory ($DST)
   -n     - dry-run
   -r     - reverse (sync dest to src)
   -D     - rsync delete (delete destination that have been deleted in src)
   -F     - full sync (see below)
   -h     - help

Full sync performs,

  1) rsync --delete SRC -> DST
  2) rsync DST -> SRC

HELP

	exit $1
}

while getopts ":hs:d:rnDF" opt; do
	case ${opt} in
		s)
			SRC=$OPTARG
			;;
		d)
			DST=$OPTARG
			;;
		r)
			let REVERSE=1
			;;
		n)
			RSOPTS="-n $RSOPTS"
			;;
		D)
			DELETE=" --delete "
			;;
		F)
			die "This is broken by pcloud since it doesn't support unix filesytem permissions/symlinks/etc"
			let FULL=1
			;;
		h) # process option a
			usage 0
			;;
		\?)
			usage 1
			;;
	esac
done

[ $FULL -eq 1 -a $REVERSE -eq 1 ] && die "Full sync shouldn't be done with reverse"

[ $FULL -eq 1 -a -n "$DELETE" ] && die "Full sync shouldn't be used with delete"

BN="$(basename $SRC)"

swap_SRC_DST() {
	# SRC <-> DST
	#SRC=/data/household/
	#DST=~/pCloudDrive/Crypto\ Folder/
	local swp=$SRC
	# SRC=~/pCloudDrive/Crypto\ Folder/household
	SRC=$DST
	# DST=/data/household
	DST=$swp
}

if [ $REVERSE -eq 1 ]; then
	swap_SRC_DST

	[ ! -d "$SRC" ] && die "Crypto folder not unlocked?"
	[ ! -d "$DST" ] && die "Dest directory not found: $SRC"

	#die "Not implemented yet"
else
	[ ! -d "$SRC" ] && die "Source directory not found: $SRC"

	DST="$DST/$BN"
	[ ! -d "$DST" ] && die "Crypto folder not unlocked?"
fi

LOG="$TMP/$BN.$NOW.log"
info "Logging to $LOG"

rsync_func() {
	let ts0=$(date +%s)

	cd "$SRC"
	[ $? -ne 0 ] && die "failed to change to source directory"

	local rsopts="$RSOPTS $DELETE"

	log "$LOG" "Working in $(pwd)"
	log "$LOG" "rsync $rsopts . to $DST"
	rsync $rsopts . "$DST/" >> "$LOG" 2>&1
	let err=$?

	let ts1=$(date +%s)
	let el=$ts1-$ts0
	log "$LOG" "rsync'd $BN in $el seconds"

	log "$LOG" "rsync returned errors: $err"
}

if [ $FULL -eq 1 ]; then
	DELETE=" --delete "
	rsync_func
	#info "before SRC=$SRC DST=$DST"
	swap_SRC_DST
	#info "after SRC=$SRC DST=$DST"
	DELETE=""
	rsync_func
else
	rsync_func
fi

#let ts0=$(date +%s)
#let cnt=0
#info "Working in $(pwd)"
#find . -type f > /var/tmp/$ME.files
#while read line; do
#	path="$(echo $line | cut -c3-)"
#	dst="$DST/$path"
#	dpath=$(dirname "$dst")
#	[ ! -d "$dpath" ] && mkdir -p -v "$dpath"
#	rsync -a "$path" "$dst"
#	[ $? -ne 0 ] && warn "failed to sync $path -> $DST/$path"
#	let cnt=$cnt+1
#	let ts1=$(date +%s)
#	let el=$ts1-$ts0
#	[ $(($cnt % 100)) -eq 0 ] && info "$cnt files synced in $el secs: $path -> $DST/$path"
#	sleep 0.010
#done < /var/tmp/$ME.files
#
#let ts1=$(date +%s)
#let el=$ts1-$ts0
#info "$cnt files synced in $el seconds"

