#!/usr/bin/env ruby
#

require 'json'
require 'fileutils'
require 'daemons'

me=$0
if File.symlink?(me)
	me=File.readlink($0)
	md=File.dirname($0)
	me=File.realpath(me)
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
YM=Time.now.strftime('%Y%m')
LOG_PATH=File.join(TMP, "#{ME}_#{YM}"+".log")

CODESEND="/var/www/html/rfoutlet/codesend"

$opts={
	:outlet=>"o1",
	:state=>"off",
	:delay=>0,
	:log => nil,
	:daemonize => false,
	:logger => $log,
	:banner => "#{ME}.rb [options] process1 ...",
	:json=>ENV["RF_OUTLET_JSON"]||File.join(MD, "rfoutlet.json")
}

$opts = OParser.parse($opts, HELP) { |opts|
	# journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"
	opts.on('-o', '--outlet NUM', String, "Outlet number") { |num|
		$opts[:outlet]="o"+num
	}

	opts.on('-0', '--off', "Outlet off") {
		$opts[:state]="off"
	}

	opts.on('-1', '--on', "Outlet on") {
		$opts[:state]="on"
	}

	opts.on('-d', '--delay TIMEOUT', Integer, "Random delay in seconds") { |delay|
		$opts[:delay]=Random.rand(0...delay)
	}

	opts.on('-j', '--json FILE', String, "JSON data file, default #{$opts[:json]}") { |json|
		if File.exists?(json)
			$log.debug "JSON data file=#{json}"
			$opts[:json]=json
		end
	}

	opts.on('-l', '--log FILE', String, "Log file name, default to logging to console") { |log|
		$opts[:log]=log
	}

	opts.on('-b', '--bg', "Daemonize the script") {
		$opts[:daemonize]=true
	}
}

def outlet(outlet, state, opts)
	on=$outlets[outlet.to_sym]
	if opts[:delay] > 0
		$log.info "Sleeping #{opts[:delay]} seconds before firing: #{on[:name]}"
		sleep opts[:delay]
	end

	$log.info "Set outlet \"#{on[:name]}\": #{state}"
	$log.info %x[#{CODESEND} #{on[state.to_sym]}].strip
end

def read_config(file)
	json=""
	begin
		json = File.read(file)
	rescue => e
		$log.die "Failed to read config #{file}: #{e}"
	end
	begin
		JSON.parse(json, :symbolize_names=>true)
	rescue
		$log.die "failed to parse json config in #{file}: #{e}"
	end
end

$outlets=read_config($opts[:json])
$log.debug JSON.pretty_generate($outlets)

if $opts[:daemonize]
	$opts[:log]=LOG_PATH if $opts[:log].nil?
	$log.debug "Daemonizing script"
	Daemons.daemonize
end

$log=Logger.set_logger($opts[:log], Logger::INFO) unless $opts[:log].nil?
$log.level = Logger::DEBUG if $opts[:debug]
$opts[:logger]=$log

o=$opts[:outlet]
s=$opts[:state]

outlet(o, s, $opts)

