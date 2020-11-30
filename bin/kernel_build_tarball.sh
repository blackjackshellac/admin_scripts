#!/bin/bash
#

MESH=$(basename $0)
ME=$(basename $0 ".sh")
MD=$(dirname $0)
KLOG_DIR="/var/tmp/$ME"

jay=$(( $(cat /proc/cpuinfo  | grep -E "^processor\s+:" | wc -l) / 2 ))
JAY=$(( $jay <= 0 ? 1 : $jay ))

let stime=$(date +%s)
#echo "$MESH: $ME: $MD: $KLOG_DIR"

puts() {
	echo -e $*
}

log_tee() {
	msg="$*"
	if [ "$quiet" == "q" ]; then
		puts "$msg" >> $klog 2>&1
	else
		puts "$msg" 2>&1 | tee -a "$klog"
	fi
}

log() {
	local level=$1
	shift
	local ts="$(date '+%x %X')"
	local msg="${level} ${ts}> $*"
	if [ -d "$KLOG_DIR" -a -f "$klog" ]; then
		log_tee "$msg"
	else
		puts "$msg"
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
	if [ "$dryrun" == "n" ]; then
		info "Dry run"
		return 0
	fi

	if [ -d "$logdir" -a -f "$klog" ]; then
		if [ "$quiet" == "q" ]; then
			$cmd >> ${klog} 2>&1
			res=$?
		else
			$cmd 2>&1 | tee -a "$klog"
			res=$?
		fi
	else
		$cmd
		res=$?
	fi
	[ $res -ne 0 ] && die "Failed execution: $cmd"
	return $res
}

# -n dry-run
# -h help
# -v verbose?
# -q quiet
# -l log
# -d log dir


usage() {
	cat - << HELP

\$ $MESH [options]

   -t TARBALL  - tarball to install
   -l LOGDIR   - log directory, default is $KLOG_DIR
   -j CPUS     - make -j CPUS (default is $JAY)
   -s START_AT - see Step values below, default is 0
   -e END_AT   - see Step values below
   -d          - don't strip debug symbols in modules_install
   -n          - dry-run
   -q          - quiet
   -h          - help

    Step  Command
     0    make
     1    make modules
     2    make modules_install
     3    make install
     4    grub2-mkconfig
     5    grubby --default-kernel

HELP

	exit $1
}


jay=$JAY
tarball=""
logdir=$KLOG_DIR
dryrun=""
quiet=""
let startat=0
let endat=10000
let strip=1

while getopts ":ht:l:j:s:e:dnqh" opt; do
	case ${opt} in
		t)
			tarball=$OPTARG
			;;
		l)
			logdir=$OPTARG
			[ -f "$logdir" ] && die "Log directory is a file: $logdir"
			;;
		j)
			let jay=$OPTARG
			;;
		s)
			let startat=$OPTARG
			;;
		e)
			let endat=$OPTARG
			;;
		d)
			let strip=0
			;;
		n)
			dryrun="n"
			;;
		q)
			warn "not implemented"
			quiet="q"
			;;
		h) # process option a
			usage 0
			;;
		\?)
			die "Unknown option: $opt"
			;;
	esac
done

[ $jay -le 0 ] && warn "Resetting invalid jay=$jay to $JAY" && jay=$JAY

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

kernel=$tarball
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

run mkdir -p $logdir

now=$(date +%Y%m%d_%H%M%S)
klog=$logdir/$ME-$now.log

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

[ $startat -le 0 -a $endat -ge 0 ] && run make -j${jay}
[ $startat -le 1 -a $endat -ge 1 ] && run make -j${jay} modules

[ $startat -le 2 -a $endat -ge 2 ] && run sudo make INSTALL_MOD_STRIP=${strip} modules_install
[ $startat -le 3 -a $endat -ge 3 ] && run sudo make install
[ $startat -le 4 -a $endat -ge 4 ] && run sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
[ $startat -le 5 -a $endat -ge 5 ] && run sudo grubby --default-kernel

[ $startat -le 6 -a $endat -ge 6 ] && run sudo cp -p $new_config /boot

let etime=$(date +%s)
let dtime=etime-stime
info "Kernel build time ${dtime} seconds"
