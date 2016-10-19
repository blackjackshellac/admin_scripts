#!/usr/bin/env ruby
#

require 'time'
require 'json'
require 'fileutils'
require 'find'

me=File.symlink?($0) ? File.readlink($0) : $0
ME=File.basename($0, ".rb")
MD=File.dirname(me)
LIB=File.realpath(File.join(MD, "..", "lib"))

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

require_relative "#{LIB}/logger"
require_relative "#{LIB}/o_parser"
require_relative "#{MD}/fwlog"

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

$opts={
	:file=>nil,
	:filter=>/Shorewall:/,
	:in=>"enp2s0",
	:logger=>$log
}

$opts = OParser.parse($opts, "") { |opts|
	opts.on('-f', '--file FILE', String, "Kernel log to parse") { |file|
		$opts[:file]=file
	}

	opts.on('-I', '--in NET_DEV', String, "Network device, default=#{$opts[:in]}") { |inp|
		$opts[:in]=inp
	}
}
$opts[:in]=/IN=#{$opts[:in]}\s/

FWLog.init($opts)

entries={}
File.open($opts[:file], "r") { |fd|
	fd.each { |line|
		e = FWLog.parse(line, $opts)
		next if e.nil?
		entries[e.src] ||= []
		entries[e.src] << e
	}
}
puts JSON.pretty_generate(entries)

