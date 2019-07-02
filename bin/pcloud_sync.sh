#!/bin/bash

ME="$(basename $0 .sh)"
MD="$(cd $(dirname $0); pwd)"
TMP="/var/tmp/$ME"
NOW="$(date +%Y%m%d_%H%M)"
RSOPTS="-v -rptgo"

source $MD/funcs.sh

mkdir -p $TMP
[ $? -ne 0 ] && die "Failed to create tmp dir $TMP"

REVERSE=0
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
   -h     - help

HELP

	exit $1
}

while getopts ":hs:d:rnD" opt; do
	case ${opt} in
		s)
			SRC=$OPTARG
			;;
		d)
			DST=$OPTARG
			;;
		r)
			REVERSE=1
			;;
		n)
			RSOPTS="-n $RSOPTS"
			;;
		D)
			RSOPTS="$RSOPTS --delete"
			;;
		h) # process option a
			usage 0
			;;
		\?)
			usage 1
			;;
	esac
done

BN="$(basename $SRC)"
if [ $REVERSE -eq 1 ]; then
	# SRC <-> DST
	#SRC=/data/household/
	#DST=~/pCloudDrive/Crypto\ Folder/
	swp=$SRC
	# SRC=~/pCloudDrive/Crypto\ Folder/household
	SRC=$DST/$BN
	# DST=/data/household
	DST=$swp

	[ ! -d "$SRC" ] && die "Crypto folder not unlocked?"
	[ ! -d "$DST" ] && die "Dest directory not found: $SRC"

	#die "Not implemented yet"
else
	[ ! -d "$SRC" ] && die "Source directory not found: $SRC"

	DST="$DST/$BN"
	[ ! -d "$DST" ] && die "Crypto folder not unlocked?"
fi

cd "$SRC"
[ $? -ne 0 ] && die "failed to change to source directory"

LOG="$TMP/$BN.$NOW.log"
info "Logging to $LOG"
let ts0=$(date +%s)
log "$LOG" "Working in $(pwd)"
log "$LOG" "rsync $RSOPTS . to $DST"
rsync $RSOPTS . "$DST/" >> "$LOG" 2>&1
let ts1=$(date +%s)
let el=$ts1-$ts0
log "$LOG" "rsync'd $BN in $el seconds"

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

