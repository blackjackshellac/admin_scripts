#!/usr/bin/env ruby
#

require 'json'
require 'fileutils'

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
LOG_PATH=File.join(TMP, ME+"_#{YM}"+".log")

CODESEND="/var/www/html/rfoutlet/codesend"

$opts={
	:outlet=>"o1",
	:state=>"off",
	:delay=>0,
	:log => nil,
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
		$opts[:delay]=delay
	}

	opts.on('-j', '--json FILE', String, "JSON data file, default #{$opts[:json]}") { |json|
		$opts[:json]=json if File.exists?(json)
	}
}
$log.level = Logger::DEBUG if $opts[:debug]
$opts[:logger]=$log

$outlets=JSON.parse(File.read($opts[:json]), :symbolize_names=>true)
puts JSON.pretty_generate($outlets)

def outlet(outlet, state)
	$log.info "Set outlet \"#{$outlets[outlet.to_sym][:name]}\": #{state}"
	puts %x[#{CODESEND} #{$outlets[outlet.to_sym][state.to_sym]}]
end

o=$opts[:outlet]
s=$opts[:state]

outlet(o, s)

