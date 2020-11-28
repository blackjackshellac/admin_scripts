#!/bin/bash
#

MESH=$(basename $0)
ME=$(basename $0 ".sh")
MD=$(dirname $0)
KLOG_DIR="/var/tmp/$ME"

#echo "$MESH: $ME: $MD: $KLOG_DIR"

puts(){
	echo -e $*
}

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
if [ ! -f "$kernel" ]; then
	puts "Choose a kernel"
	puts $(ls -1 linux-*.tar.*)
	read -p "> " kernel
	[ ! -f "$kernel" ] && die "Kernel not found $kernel"
	info "Using kernel $kernel"
fi

kernel=$(basename $kernel)
wdir=$(dirname $kernel)
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

dot_config="$(pwd)/${kdir}/.config"
new_config="$(pwd)/config-${kdir}"
sym_config="$(pwd)/config-latest"
run_make_oldconfig=0
if [ -f "$dot_config" ]; then
	warn "Skipping config file copy to $dot_config, file already exists"
else
	run cp -v $sym_config $dot_config
	[ ! -f "$dot_config" ] && die "Failed to copy config-latest to $kdir/.config"
	run_make_oldconfig=1
fi

cd $kdir
[ $? -ne 0 ] && die "Failed to change working directory to $kdir"

[ $run_make_oldconfig -ne 0 ] && run make oldconfig

cmp -s "$new_config" "$dot_config"
[ $? -ne 0 ] && run cp -pv $dot_config $new_config
run ln -sf $new_config $sym_config

run make -j4
run make -j4 modules

run sudo make INSTALL_MOD_STRIP=1 modules_install
run sudo make install
run sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
run sudo grubby --default-kernel


