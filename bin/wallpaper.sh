#!/bin/bash

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	# grep for gnome-session-binary (pgrep limited to 15 characters)
	PID=$(pgrep -u $LOGNAME gnome-session)
	if [ -z "$PID" ]; then
		echo "Error: gnome-session not running for user $LOGNAME"
		exit 1
	fi
	# cat /proc/${PID}/environ | grep -z DBUS_SESSION_BUS_ADDRESS | tr '\0' '\n'
	export DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$PID/environ| tr '\0' '\n'|cut -d= -f2-)
#else
#	echo $DBUS_SESSION_BUS_ADDRESS
fi

file="file://$(find ${HOME}/Pictures/wallpaper/ -type f | shuf -n1)"
[ -z "$file" ] && echo "No file selected" && exit 1
cmd="gsettings set org.gnome.desktop.background picture-uri $file"
#echo $cmd
$cmd
