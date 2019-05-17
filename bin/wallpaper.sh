#!/bin/bash

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	PID=$(pgrep -u $LOGNAME gnome-session)
	export DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$PID/environ|cut -d= -f2-)
#else
#	echo $DBUS_SESSION_BUS_ADDRESS
fi

file="file://$(find ${HOME}/Pictures/wallpaper/ -type f | shuf -n1)"
[ -z "$file" ] && echo "No file selected" && exit 1
cmd="gsettings set org.gnome.desktop.background picture-uri $file"
#echo $cmd
$cmd
