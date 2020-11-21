#!/bin/bash
#
# Update given hosts from packages in dnf cache directory /var/cache/dnf/updates-...
#

ME=$(basename $0)

DNF_CACHE=/var/cache/dnf

hosts=$*
update_dir=$(ls -1rtd $DNF_CACHE/updates-[0-9a-f][0-9a-f]* | tail -1)

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

test_hosts() {
	for host in $hosts; do
		echo Testing $host
		ssh $host echo > /dev/null
		[ $? -ne 0 ] && die "Failed to connect to $host"
	done
}

indent=">>>>>"
run_echo() {
	cmd=$*
	info "\n$indent\n$indent $cmd"
	$cmd
	return $?
}

test_hosts $hosts

run_echo dnf -y update

cd ${update_dir}
[ $? -ne 0 ] && die "Failed to change to updates directory ${update_dir}"

# [ -z "$(find packages/ -type f)" ] && echo Nothing

let do_rsync=1
[ ! -d "packages" -o -z "$(find packages/ -type f)" ] && warn "No cached packages to update" && let do_rsync=0

let errors=0
for host in $hosts; do
	if [ $do_rsync -eq 1 ]; then
		info "Updating cached packages on $host from $(pwd)"
		run_echo rsync -av "packages/*.rpm" $host:$(pwd)/packages/
		ret=$?
		[ $ret -ne 0 ] && err "Failed to rsync packages to ${host}: ${ret}" && let errors=$errors+1 && continue
	fi
	run_echo ssh $host dnf -y update
	[ $? -ne 0 ] && err "Failed to update packages on ${host}" && let errors=$errors+1 && continue
	run_echo ssh $host rm -f "${update_dir}/packages/*.rpm"
	[ $? -ne 0 ] && err "Failed to remove packages on ${host}" && let errors=$errors+1 && continue
done

if [ $errors -eq 0 ]; then
	rm -fv packages/*
	cd $DNF_CACHE
	# deleting older cached files
	info "Deleting older cached files in $DNF_CACHE"
	find -type f -name '*.rpm' -mtime +7 -print -delete
fi
