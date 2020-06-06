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

let do_rsync=1
[ ! -d "packages" -o -z "$(find packages/ -type f)" ] && warn "No cached packages to update" && let do_rsync=0

indent=">>>>>"
run_echo() {
	cmd=$*
	info "\n$indent\n$indent $cmd"
	$cmd
	return $?
}

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

[ $errors -eq 0 ] && rm -fv packages/*

