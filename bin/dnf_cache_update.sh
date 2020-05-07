#!/bin/bash
#
# Update given hosts from packages in dnf cache directory /var/cache/dnf/updates-...
#

ME=$(basename $0)

hosts=$*
update_dir=$(ls -1rtd /var/cache/dnf/updates-[0-9a-f][0-9a-f]* | tail -1)

info() {
	echo -e "$*"
}

warn() {
	info "Warn: $*"
}

err() {
	info "Error: $*"
}

die() {
	err $*
	exit 1
}

[ -z "$hosts" ] && info "Usage is ${ME} host ..." && exit 0

dnf -y update

cd ${update_dir}
[ $? -ne 0 ] && die "Failed to change to updates directory ${update_dir}"

# [ -z "$(find packages/ -type f)" ] && echo Nothing
[ ! -d "packages" -o -z "$(find packages/ -type f)" ] && warn "No packages to update" && exit 0

let errors=0
for host in $hosts; do
	rsync -av packages $host:$(pwd)/
	[ $? -ne 0 ] && err "Failed to rsync packages to ${host}" && let errors=$errors+1 && continue
	ssh $host dnf -y update
	[ $? -ne 0 ] && err "Failed to update packages on ${host}" && let errors=$errors+1 && continue
	ssh $host rm -f ${update_dir}/packages/*
	[ $? -ne 0 ] && err "Failed to remove packages on ${host}" && let errors=$errors+1 && continue
done

[ $errors -eq 0 ] && rm -fv packages/*

