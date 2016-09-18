#!/bin/bash

DEBUG="${DEBUG:-0}"

info() {
	echo -e $*
}

warn() {
	info "Warning: $*"
}

err() {
	info "Error: $*"
}

die() {
	err $*
	exit 1
}

debug() {
	[ -z "$DEBUG" ] && return
	[ "$DEBUG" == "0" ] && return
	info "Debug: $*"
}
