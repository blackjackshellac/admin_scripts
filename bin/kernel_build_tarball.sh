#!/bin/bash
#

MESH=$(basename $0)
ME=$(basename $0 ".sh")
MD=$(dirname $0)
KLOG_DIR="/var/tmp/$ME"

jay=$(( $(cat /proc/cpuinfo  | grep -E "^processor\s+:" | wc -l) / 2 ))
JAY=$(( $jay <= 0 ? 1 : $jay ))

declare -i stime=$(date +%s)
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
	local ts="$(LC_TIME="fr_CA.UTF-8" date '+%x %X')"
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

runsudo() {
	local -i t0=$(date +%s)
	if [ -z "$sudo_pass" ]; then
		sudo --validate
	else
		echo "$sudo_pass" | sudo --validate --stdin
	fi
	local -i t1=$(date +%s)
	declare -gi t_sudo_pause=$(( t_sudo_pause+t1-t0 ))
	run sudo $*
	return $?
}

convertsecs() {
	((h=${1}/3600))
	((m=(${1}%3600)/60))
	((s=${1}%60))
	[ $h -gt 0 ] && printf "%dh " $h
	[ $h -gt 0 -o $m -gt 0 ] && printf "%dm " $m
	printf "%ds\n" $s
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

   -k KVER     - kernel version (eg 5.9.11)
   -t TARBALL  - tarball to install
   -c CONFIG   - config file to use, default is config-linux-KERNEL_VERSION
   -l LOGDIR   - log directory, default is $KLOG_DIR
   -j CPUS     - make -j CPUS (default is $JAY)
   -s START_AT - see Step values below, default is 0
   -e END_AT   - see Step values below
   -p          - prompt for sudo password
   -P          - patch the given kernel directory from kernel.org
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

kdir=""
jay=$JAY
tarball=""
new_config=""
logdir=$KLOG_DIR
dryrun=""
quiet=""
sudo_pass=""
declare -i startat=0
declare -i endat=10000
declare -i strip=1


while getopts ":hk:t:c:l:j:s:e:dpPnqh" opt; do
	case ${opt} in
		k)
			kver=$OPTARG
			kdir=linux-${kver}
			tarball=${kdir}.tar.xz
			;;
		t)
			tarball=$OPTARG
			;;
		c)
			new_config=$OPTARG
			;;
		l)
			logdir=$OPTARG
			[ -f "$logdir" ] && die "Log directory is a file: $logdir"
			;;
		j)
			jay=$OPTARG
			;;
		s)
			startat=$OPTARG
			;;
		e)
			endat=$OPTARG
			;;
		d)
			strip=0
			;;
		p)
			read -s -e -p "sudo password: " sudo_pass
			echo "$sudo_pass" | sudo -k --validate --stdin
			[ $? -ne 0 ] && die "Invalid sudo password"
			;;
		P)
			# patch
			patch=1
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
if [ ! -f "$kernel" -a -z $kdir ]; then
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

[ -z "${kdir}" ] && kdir=$(basename $kernel ".tar.xz")

run mkdir -p $logdir

now=$(date +%Y%m%d_%H%M%S)
klog=$logdir/$ME-$now.log

touch $klog
info "Logging to $klog"

info kernel=$kernel
info kdir=$kdir

if [ $patch -eq 1 ]; then
	knam=$(echo $kdir | cut -d'-' -f1)
	kver=$(echo $kdir | cut -d'-' -f2-)
	declare -i kmaj=$(echo $kver | cut -d'.' -f1)
	declare -i kmin=$(echo $kver | cut -d'.' -f2)
	declare -i kpat=$(echo $kver | cut -d'.' -f3)
	declare -i kinc=$(( kpat + 1 ))
	knew="${knam}-${kmaj}.${kmin}.${kinc}"

	[ -d "${knew}" ] && die "Patched kernel directory already exists: ${knew}"

	# wget https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.9.11-12.xz
	# cd linux-5.9.11
	# $ xzcat ../patch-5.9.11-12.xz | patch --dry-run -p1
	patch="patch-${kver}-${kinc}.xz"
	url_patch="https://mirrors.edge.kernel.org/pub/linux/kernel/v${kmaj}.x/incr/${patch}"
	info "Kernel version to patch is $kver (v${kmaj}.x) -> $patch"
   if [ -f ${patch} ]; then
		warn "Patch file already exists: ${patch}"
	else
		run wget $url_patch
	fi
	cd $kdir
	[ $? -ne 0 ] && die "Original kernel directory not found: $kdir"
	popts="--quiet --forward -p1"
	[ "$dryrun" == "n" ] && popts="$popts --dry-run"
	info "Applying $patch to $kdir"
	run xzcat ../${patch} | patch ${popts}
	cd ..
	run mv --verbose $kdir $knew
	exit 1
fi

if [ -d "$kdir" ]; then
	warn "Kernel directory already exists, skipping tar xf $kernel"
else
	run tar xf $kernel
	[ $? -ne 0 ] && die "Failed to untar $kernel"
fi

dot_config="$(pwd)/${kdir}/.config"
sym_config="$(pwd)/config-latest"

[ -z "$new_config" ] && new_config="$(pwd)/config-${kdir}"
if [ ! -f "$new_config" ]; then
	if [ -f "${kdir}"/.config ]; then
		cp -pv "${kdir}"/.config "$new_config"
	elif [ -f /boot/config-${kdir} ]; then
		cp -pv /boot/config-${kdir} $new_config
	elif [ -L $sym_config -a -f $sym_config ]; then
		cp -pv $sym_config $new_config
	else
		die "Config file not found, use -c option to choose a config file"
	fi
fi
# [ ! -f "$new_config" ] && new_config=$sym_config
# [ ! -f "$new_config" ] && new_config="/boot/config-${kdir}"
# [ ! -f "$new_config" ] && die "Config file not found, use -c option to choose a config file"

run_make_oldconfig=0
if [ -f "$dot_config" ]; then
	warn "Skipping config file copy to $dot_config, file already exists"
else
	cp -pv "$new_config" "$dot_config"
	[ ! -f $dot_config ] && die "Failed to copy $new_config to $dot_config"
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

[ $startat -le 2 -a $endat -ge 2 ] && runsudo make INSTALL_MOD_STRIP=${strip} modules_install
[ $startat -le 3 -a $endat -ge 3 ] && runsudo make install
[ $startat -le 4 -a $endat -ge 4 ] && runsudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
[ $startat -le 5 -a $endat -ge 5 ] && runsudo grubby --default-kernel
[ $startat -le 6 -a $endat -ge 6 ] && runsudo cp -p $new_config /boot

declare -i etime=$(date +%s)
declare -i dtime=$(( etime-stime-t_sudo_pause ))
info "Kernel build time $(convertsecs $dtime) - sudo wait $(convertsecs $t_sudo_pause)"
