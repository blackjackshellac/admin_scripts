#!/bin/bash

ME=$(basename $0)
MD=$(dirname $0)

source "${MD}/funcs.sh"

WALLPAPERS=${WALLPAPERS:-"${HOME}/Pictures/wallpaper/"}
[ ! -d "$WALLPAPERS" ] && die "Wallpaper directory not found: ${WALLPAPERS}"

GSETTINGS=$(type -p gsettings)
[ $? -ne 0 ] && die "gsettings not found"

SHUF=$(type -p shuf)
[ $? -ne 0 ] && die "shuf not found"

IMG=$(find ${WALLPAPERS} -type f | ${SHUF} -n1)
debug $IMG

debug ${GSETTINGS} set org.gnome.desktop.background picture-uri "file:///${IMG}"
${GSETTINGS} set org.gnome.desktop.background picture-uri "file:///${IMG}"
[ $? -ne 0 ] && die "failed to set background image ${IMG}"
exit 0
