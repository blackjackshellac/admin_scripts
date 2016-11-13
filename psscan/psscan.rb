#!/usr/bin/env ruby
#
#

require 'time'
require 'json'
require 'fileutils'

me=$0
if File.symlink?(me)
	me=File.readlink($0)
	md=File.dirname($0)
	me=File.realpath(File.join(md, me))
end
ME=File.basename(me, ".rb")
MD=File.dirname(me)
LIB=File.realpath(File.join(MD, "..", "lib"))

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")
HELP=File.join(MD, ME+".help")

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

SUSPEND_FILE=File.join(TMP, "suspend.ts")

$opts={
	:user => nil,
	:kill => "TERM",
	:dryrun => false,
	:cancel => false,
	:logger => $log,
	:banner => "#{ME}.rb [options] process1 ..."
}

$opts = OParser.parse($opts, HELP) { |opts|
	# journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"

	opts.on('-u', '--user NAME', String, "User name to monitor") { |user|
		$opts[:user]=user
	}

	opts.on('-k', '--kill SIG', String, "Process signal, def=#{$opts[:kill]}") { |sig|
		$opts[:kill] = sig
	}
	
	opts.on('-n', '--[no-]dry-run', "Don't actually kill the process") {
		$opts[:dryrun] = true
	}

	opts.on('-s', '--until DATE', String, "Suspend kill until given date") { |date|
		$opts[:until] = date
	}

	opts.on('-c', '--cancel', "Cancel suspend timeout") {
		$opts[:cancel]=true
	}
}

def cancel_suspend
	$log.info "Cancelling suspend timeout: #{File.read(SUSPEND_FILE).strip}"
	puts %x/rm #{SUSPEND_FILE} 2>&1/
end

if $opts[:until]
	ds=%x/date --date "#{$opts[:until]}" --iso-8601=ns 2>&1/.strip
	$log.die "Date command failed #{ds}" if !$?
	$log.info "Suspending operation until #{ds}"
	File.umask(0022)
	File.open(SUSPEND_FILE, "w") { |fd|
		fd.puts ds
	}
	exit
end

if File.exist?(SUSPEND_FILE)
	if $opts[:cancel]
		cancel_suspend
	else
		ds=File.read(SUSPEND_FILE).strip
		ts=Time.parse(ds)
		now=Time.now
		$log.debug "ds=#{ds} ts=#{ts} now=#{now}"
		if now < ts
			$log.debug "Suspend timeout not reached, exiting"
			exit
		else
			$log.debug "Reached suspend timeout, delete #{SUSPEND_FILE}"
			cancel_suspend
		end
	end
end

def getps(u, p)
	%x/pgrep -u #{u} #{p}/.strip
end

u=$opts[:user]
k=$opts[:kill]
n=$opts[:dryrun]
dr=n ? " - dryrun" : ""

if u.nil?
	$log.die "User not supplied" unless $opts[:cancel]
	exit
end
$log.die "No processes supplied" if ARGV.empty?

errors=0
# pkill -u #{u} --signal
ARGV.each { |p|
	ps=getps(u, p)
	if ps.empty?
		$log.debug "Process #{p} not found for user #{u}"
		next
	end

	cmd="pkill -u #{u} --signal #{k} #{p}"
	$log.debug "#{ps}: Running #{cmd}#{dr}"
	unless n
		puts %x/#{cmd}/
		sl=5
		sleep sl
		ps=getps(u, p)
		unless ps.empty?
			$log.error "Failed to kill #{p} for user #{u} after #{sl} seconds"
			errors+=1
		end
	end
}

$log.die "#{errors} processes failed to terminate properly" unless errors == 0

