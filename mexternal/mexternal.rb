#!/usr/bin/env ruby
#

require 'optparse'
require 'logger'
require 'json'
require 'fileutils'

require_relative 'lib/host_config'
require_relative 'lib/devices'

ME=File.basename($0, ".rb")
md=File.dirname($0)
FileUtils.chdir(md) {
	md=Dir.pwd().strip
}
MD=md
HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

hc=HostConfig.new()
hc.from_file(CFG_PATH)

class Logger
	def die(msg)
		$stdout = STDOUT
		self.error(msg)
		exit 1
	end

	def puts(msg)
		self.info(msg)
	end

	def write(msg)
		self.info(msg)
	end
end

def set_logger(stream, level=Logger::INFO)
	log = Logger.new(stream)
	log.level = level
	log.datetime_format = "%Y-%m-%d %H:%M:%S"
	log.formatter = proc do |severity, datetime, progname, msg|
		"#{severity} #{datetime}: #{msg}\n"
	end
	log
end

$log=set_logger(STDERR)

$opts={
	:mount=>true,
	:list=>false,
	:scripts=>["ls -l"],
	:default=>"default",
	:name=>nil
}

def parse(gopts)
	begin
		optparser = OptionParser.new { |opts|
			opts.banner = "#{ME}.rb [options]\n"

			opts.on('-m', '--mount', "Mount the first known device found") {
				gopts[:mount]=true
			}

			opts.on('-u', '--umount', "Unmount the ") {
				gopts[:mount]=false
			}

			opts.on('-p', '--print', "Print the configuration") {
				printCfg(CFG)
				exit 0
			}

			opts.on('-l', '--list', "List devices by-id") {
				puts %x[ls -l /dev/disk/by-id]
				exit 0
			}

			opts.on('-n', '--name NAME', String, "Set config name, default=#{$opts[:default]}") { |name|
				$opts[:name]=name
			}

			opts.on('-a', '--add DEV', String, "Add device path") { |dev|
				addDev($opts[:name], dev)
				exit 0
			}

			opts.on('-x', '--exe SCRIPT', String, "Add script to execute after mount") { |script|
				gopts[:scripts] << script
			}

			opts.on('-D', '--debug', "Debug logging") {
				gopts[:debug]=true
				$log.level = Logger::DEBUG
				$log.debug "Debugging enabled"
			}

			opts.on('-h', '--help', "Help") {
				$stdout.puts opts
				$stdout.puts <<HELP
HELP
				exit 0
			}
		}
		optparser.parse!
	rescue OptionParser::InvalidOption => e
		$log.die e.message
	rescue => e
		$log.die e.message
	end

	gopts
end

parse($opts)

hcc=hc.getHostConfig()
nc=hcc.getNameConfig()
puts nc.getName
puts nc.getMountPoint
puts nc.getDevices
puts nc.getMapper
puts nc.getOptions

nc.getDevices.each { |dev|
	next unless Devices.found(dev)
	$log.info "Found #{dev}"
	if Devices.isLuks(dev)
		Devices.openLuks(dev, nc.getName)
		dev=nc.getMapper
	end
	Devices.mountDev(dev, nc.getMountPoint, nc.getOptions)
	break
}
