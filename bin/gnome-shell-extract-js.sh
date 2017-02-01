#!/bin/bash
#
# updated from here,
#
# https://blogs.gnome.org/mclasen/2014/03/24/keeping-gnome-shell-approachable/
#

gs=/usr/lib64/gnome-shell/libgnome-shell.so

[ ! -f "$gs" ] && echo "Error: file not found: $gs" && exit 1

base=$HOME/gnome-shell-js
mkdir -pv "$base"
cd "$base"

echo "Working in $base"

#for d in ui/components ui/status misc perf extensionPrefs gdm; do
#	mkdir -pv "$base/$d"
#done

for r in `gresource list $gs`; do
	src=$r
	dst=${r/#\/org\/gnome\/shell/.}
	[ -f $dst ] && echo "File already exists: $dst" && continue
	echo "Extract $src to $dst"
	ddir=$(dirname $dst)
	[ ! -d $ddir ] && mkdir -pv $ddir
	gresource extract $gs $r > ${r/#\/org\/gnome\/shell/.}
done
