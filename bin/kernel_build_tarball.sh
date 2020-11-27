#!/bin/bash
#

MESH=$(basename $0)
ME=$(basename $0 ".sh")
MD=$(dirname $0)
KLOG_DIR="/var/tmp/$ME"

#echo "$MESH: $ME: $MD: $KLOG_DIR"

log() {
	local level=$1
	shift
	local ts="$(date '+%x %X')"
	local msg="${level} ${ts}> $*"
	if [ -d "$KLOG_DIR" -a -f "$klog" ]; then
		echo -e "$msg" 2>&1 | tee -a "$klog"
	else
		echo -e "$msg"
	fi
}

info() {
	log "INFO" $*
}

warn() {
	log "WARN" $*
}

err() {
	log "ERROR" $*
}

die() {
	log "FATAL" $*
	exit 1
}

run() {
	cmd=$*
	info "run: $cmd"
	if [ -d "$KLOG_DIR" -a -f "$klog" ]; then
		$cmd 2>&1 | tee -a "$klog"
		res=$?
	else
		$cmd
		res=$?
	fi
	[ $res -ne 0 ] && die "Failed execution: $cmd"
	return $res
}

# linux-5.9.11.tar.xz

# tar xf linux-5.8.18.tar.xz
# cd linux-5.8.18/
# cp /boot/config-5.8.18-200.fc32.x86_64 .config
# make oldconfig
# make -j4
# make -j4 modules
# sudo make modules_install
# sudo make install
# sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
# sudo grubby --default-kernel

kernel=$1
[ ! -f "$kernel" ] && die "Kernel not found $kernel"

kernel=$(basename $1)
wdir=$(dirname $1)
cd $wdir
[ $? -ne 0 ] && die "Failed to change working directory to kernel working dir $wdir"
info "Working in $wdir: $(pwd)"

kdir=$(basename $kernel ".tar.xz")

run mkdir -p $KLOG_DIR

now=$(date +%Y%m%d_%H%M%S)
klog=$KLOG_DIR/$ME-$now.log

touch $klog
info "Logging to $klog"

info kernel=$kernel
info kdir=$kdir

if [ -d "$kdir" ]; then
	warn "Kernel directory already exists, skipping tar xf $kernel"
else
	run tar xf $kernel
	[ $? -ne 0 ] && die "Failed to untar $kernel"
fi

if [ -f $kdir/.config ]; then
	warn "Skipping config file copy to $kdir/.config, file already exists"
else
	run cp -v config-latest $kdir/.config
	[ ! -f "$kdir/.config" ] && die "Failed to copy config-latest to $kdir/.config"
fi

cd $kdir
[ $? -ne 0 ] && die "Failed to change working directory to $kdir"

run make oldconfig
run make -j4
run make -j4 modules

