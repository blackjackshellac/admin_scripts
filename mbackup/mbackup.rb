#!/usr/bin/env ruby
#

require 'optparse'
require 'logger'
require 'json'
require 'fileutils'

ME=File.basename($0, ".rb")
md=File.dirname($0)
FileUtils.chdir(md) {
	md=Dir.pwd().strip
}
MD=md
HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

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

def loadCfg(path)
	begin
		json=File.read(path)
		JSON.parse(json, :symbolize_names=>true)
	rescue => e
		e.backtrace.each { |bt| puts bt }
		$log.die e.message
	end
end

def saveCfg(path)
	begin
		File.open(path, "w+") { |fd|
			fd.puts JSON.pretty_generate(CFG)
		}
	rescue => e
		e.backtrace.each { |bt| puts bt }
		$log.die e.message
	end
end

def getHostCfg(create=false)
	hosts=CFG[:hosts]||{}
	hcfg=hosts[HOSTNAME_S]
	if hcfg.nil?
		if create
			hcfg={}
			hosts[HOSTNAME_S]=hcfg
			CFG[:hosts]=hosts
		else
			hcfg=CFG
		end
	end
	$log.debug "hcfg="+hcfg.inspect
	hcfg
end

def printCfg(cfg)
	$stdout.puts JSON.pretty_generate(cfg)
end

CFG=loadCfg(CFG_PATH)

def getHostDevices()
	hcfg=getHostCfg(true)
	hcfg[:devices]=[] unless hcfg.key?(:devices)
	hcfg[:devices]
end

def addDev(dev)
	devices=getHostDevices
	if devices.include?(dev)
		$log.warn "Device #{dev} already exists"
	else
		raise "Device not found: #{dev}" unless File.exists?(dev)
		devices << dev
		saveCfg(CFG_PATH)
	end
	printCfg(CFG)
end

def addName(name)
	hcfg=getHostCfg(true)
	$log.warn "Overwriting name=#{hcfg[:name]}" if hcfg.key?(:name)
	hcfg[:name]=name
	hcfg[:mountpoint]=name unless hcfg.key?(:mountpoint)
	saveCfg(CFG_PATH)
	printCfg(CFG)
end

$opts={
	:mount=>true,
	:list=>false,
	:scripts=>["ls -l"]
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

			opts.on('-n', '--name NAME', String, "Set device name and mountpoint for this host") { |name|
				addName(name)
				exit 0
			}

			opts.on('-a', '--add DEV', String, "Add device path") { |dev|
				addDev(dev)
				exit 0
			}

			opts.on('-x', '--exe SCRIPT', String, "Add script to execute after mount") { |script|
				gopts[:scripts] << script
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

def run(cmd)
	puts cmd
	puts %x[#{cmd}]
end

def isLuks(dev)
	run("cryptsetup isLuks #{dev}")
	return ($?.exitstatus == 0)
end

def openLuks(dev, name)
	raise "Device #{dev} is not a luks device" unless isLuks(dev)
	mapper="/dev/mapper/#{name}"
	unless File.exists?(mapper)
		run("cryptsetup open --type luks #{dev} #{name}")
		raise "Failed to unlock luks device #{name}" unless $?.exitstatus == 0
	end
	return mapper
end

def mountDev(dev, mp, options="")
	options="" if options.nil?
	run("mount #{options} #{dev} #{mp}")
	raise "Failed to mount #{dev} #{mp}" unless $?.exitstatus == 0
end

def runScripts(mp)
	$opts[:scripts].each { |script|
		run("#{script} #{mp}")
		raise "Failed to run #{script} #{mp}" unless $?.exitstatus == 0
	}
end

# CFG keys are symbols
hcfg=getHostCfg(false)

mp=hcfg[:mountpoint]
name=hcfg[:name]

unless hcfg[:scripts].nil?
		$opts[:scripts].concat(hcfg[:scripts])
		$log.info "Scripts="+$opts[:scripts].inspect
end

if $opts[:mount]
	# cryptsetup open --type luks /dev/sdg1 backup	
	hcfg[:devices].each { |dev|
		$log.info "Trying device #{dev}"
		if File.exists?(dev)
			begin
				mapper=openLuks(dev, name)
				mountDev(mapper, mp, hcfg[:options])
				runScripts(mp)
				exit 0
			rescue => e
				$log.error e.message
			end
		end
	}
else
	run("umount #{mp}")
	run("cryptsetup close --type luks #{name}")
end

