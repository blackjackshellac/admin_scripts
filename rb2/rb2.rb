#!/usr/bin/env ruby
#
#

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
require_relative File.join(MD, "rb2conf")

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)
YM=Time.now.strftime('%Y%m')
LOG_PATH=File.join(TMP, "#{ME}_#{YM}"+".log")

$opts={
	:daemonize => false,
	:logger => $log,
	:banner => "#{ME}.rb [options] process1 ...",
	:json=>ENV["RF_OUTLET_JSON"]||File.join(MD, "rfoutlet.json")
}

$opts = OParser.parse($opts, HELP) { |opts|
	# journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"
	opts.on('-b', '--bg', "Daemonize and run in background") {
		$opts[:daemonize]=true
	}
}

$log.debug $opts.inspect

Rb2Config.init($opts)
rb2c = Rb2Config.new
puts JSON.pretty_generate(rb2c)

rb2c.save_config #(Rb2Config::CONF_ROOT)

