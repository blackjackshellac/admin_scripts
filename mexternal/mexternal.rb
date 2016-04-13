#!/usr/bin/env ruby
#

require 'optparse'
require 'logger'
require 'json'
require 'fileutils'

require_relative 'lib/host_config'
require_relative 'lib/devices'
require_relative 'lib/logger'

ME=File.basename($0, ".rb")
md=File.dirname($0)
FileUtils.chdir(md) {
	md=Dir.pwd().strip
}
MD=md
HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

$log=set_logger(STDERR)

hc=HostConfig.new()
hc.from_file(CFG_PATH)

$opts={
	:action=>:MOUNT,
	:scripts=>["ls -l"],
	:default=>"default",
	:name=>nil
}

def parse(gopts)
	begin
		optparser = OptionParser.new { |opts|
			opts.banner = "#{ME}.rb [options]\n"

			opts.on('-m', '--mount', "Mount the first known device found") {
				gopts[:action]=:MOUNT
			}

			opts.on('-u', '--umount', "Unmount the currently mounted device") {
				gopts[:action]=:UMOUNT
			}

			opts.on('-p', '--print', "Print the configuration") {
				gopts[:action]=:PRINT
			}

			opts.on('-l', '--list', "List devices by-id") {
				gopts[:action]=:LIST
			}

			opts.on('-n', '--name NAME', String, "Set config name, default=#{$opts[:default]}") { |name|
				$opts[:name]=name
			}

			opts.on('-a', '--add DEV', String, "Add device path") { |dev|
				# TODO addDev($opts[:name], dev)
				exit 0
			}

			opts.on('-x', '--exe SCRIPT', String, "Add script to execute after mount") { |script|
				gopts[:scripts] << script
				# TODO
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

$log.debug "Hostconfig="+hc.inspect

# these actions don't require a host specific config
case $opts[:action]
when :LIST
	$log.debug "Action="+$opts[:action].to_s
	Devices.run("ls -l /dev/disk/by-id/")
	exit $?.exitstatus
when :PRINT
	$log.debug "Action="+$opts[:action].to_s
	hc.print
	exit
end

# get config for this host
hcc=hc.getHostConfig()

nc=hcc.getNameConfig()
#puts nc.getName
#puts nc.getMountPoint
#puts nc.getDevices
#puts nc.getMapper
#puts nc.getOptions

mp = nc.getMountPoint()

case $opts[:action]
when :MOUNT
	$log.debug "Action="+$opts[:action].to_s
	nc.getDevices.each { |dev|
		next unless Devices.found(dev)
		$log.info "Found #{dev}"
		if Devices.isLuks(dev)
			Devices.openLuks(dev, nc.getName)
			dev=nc.getMapper
		end
		Devices.mountDev(dev, mp, nc.getOptions)
		Devices.runScripts(mp, nc.getScripts($opts[:scripts]))
		break
	}
when :UMOUNT
	$log.debug "Action="+$opts[:action].to_s
	Devices.run("umount #{mp}")
	Devices.run("cryptsetup close --type luks #{nc.getName}")
else
	$log.die "Unknown action: "+$opts[:action].inspect
end

