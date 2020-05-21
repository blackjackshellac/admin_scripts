#!/bin/bash

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	# grep for gnome-session-binary (pgrep limited to 15 characters)
	# ps -u steeve -f | grep gnome-session-binary | grep systemd-service | awk '{printf $2}'
	#PID=$(pgrep -u $LOGNAME gnome-session)
	#/run/user/1201/bus
	BUS=/run/user/$(id -u $LOGNAME)/bus
	[ ! -S "$BUS" ] && echo "Error: dbus not found at $BUS" && exit 1
	DBUS_SESSION_BUS_ADDRESS="unix:path=$BUS"
	export DBUS_SESSION_BUS_ADDRESS
	#echo $DBUS_SESSION_BUS_ADDRESS
	#PID=$(ps -u $LOGNAME -f | grep gnome-session-binary | grep systemd-service | awk '{printf $2}')
	#if [ -z "$PID" ]; then
	#	echo "Error: gnome-session not running for user $LOGNAME"
	#	exit 1
	#fi
	# cat /proc/${PID}/environ | grep -z DBUS_SESSION_BUS_ADDRESS | tr '\0' '\n'
	#export DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$PID/environ| tr '\0' '\n'|cut -d= -f2-)
	#echo $DBUS_SESSION_BUS_ADDRESS
fi

file="file://$(find ${HOME}/Pictures/wallpaper/ -type f | shuf -n1)"
#echo gsettings set org.gnome.desktop.background picture-uri "$file"
gsettings set org.gnome.desktop.background picture-uri "$(echo -E $file)"
res=$?
#if [ $res -ne 0 ]; then
#	echo "Failed to set $file as background picture-uri"
#fi
exit $res
