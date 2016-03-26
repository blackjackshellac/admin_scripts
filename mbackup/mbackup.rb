#!/usr/bin/env ruby
#

require 'optparse'
require 'logger'
require 'json'
require 'fileutils'

ME=File.basename($0, ".rb")
md=File.dirname($0)
FileUtils.chdir(md) {
	md=%x/pwd/.strip
}
MD=md
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
		cfg=JSON.parse(json, :symbolize_names=>true)
	rescue => e
		e.backtrace.each { |bt| puts bt }
		$log.die e.message
	end
	cfg
end

def saveCfg(path, cfg)
	begin
		File.open(path, "w+") { |fd|
			fd.puts JSON.pretty_generate(cfg)
		}
	rescue => e
		e.backtrace.each { |bt| puts bt }
		$log.die e.message
	end
end

def printCfg(cfg)
	$stdout.puts JSON.pretty_generate(cfg)
end

CFG=loadCfg(CFG_PATH)

def addDev(dev, cfg)
	devices=cfg[:devices]
	if devices.include?(dev)
		$log.warn "Device #{dev} already exists"
	else
		raise "Device not found: #{dev}" unless File.exists?(dev)
		devices << dev
		saveCfg(CFG_PATH, cfg)
	end
	printCfg(cfg)
end

$opts={
	:mount=>true,
	:list=>false
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

			opts.on('-a', '--add DEV', String, "Add device path") { |dev|
				addDev(dev, CFG)
				exit 0
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

mp=CFG[:mountpoint]
name=CFG[:name]
if $opts[:mount]
	# cryptsetup open --type luks /dev/sdg1 backup	
	CFG[:devices].each { |dev|
		$log.info "Trying device #{dev}"
		if File.exists?(dev)
			begin
				mapper=openLuks(dev, name)
				mountDev(mapper, mp, CFG[:options])
				run("ls -l #{mp}")
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

