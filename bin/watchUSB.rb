#!/usr/bin/env ruby
#

require 'json'

def libdir(ldir)
	md=File.absolute_path(File.dirname(ldir))
	if File.symlink?(ldir)
		ldir=File.dirname(File.expand_path(File.join(md, File.readlink(ldir))))
	else
		ldir=File.dirname(ldir)
	end
	ldir=File.join(ldir, "../lib")
	File.expand_path(ldir)
end

ME=File.basename($0, ".rb")
MD=File.absolute_path(File.dirname($0))
LD=libdir($0)

# quick command line args
update=ARGV.include?("update")
debug=ARGV.include?("debug")
help=ARGV.include?("help")
quiet=ARGV.include?("quiet")
if help
	puts "#{ME} [update|debug|help|quiet]"
	exit
end

require_relative File.join(LD, "logger")

$log = Logger.set_logger(STDERR)
if quiet
	$log.level = Logger::WARN
elsif debug
	$log.level = Logger::DEBUG
end

#Bus 002 Device 002: ID 8087:8000 Intel Corp. 
#Bus 002 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
#Bus 001 Device 002: ID 8087:8008 Intel Corp. 
#Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
#Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
#Bus 003 Device 005: ID 0a12:0001 Cambridge Silicon Radio, Ltd Bluetooth Dongle (HCI mode)
#Bus 003 Device 003: ID 046d:c018 Logitech, Inc. Optical Wheel Mouse
#Bus 003 Device 010: ID 18d1:4ee1 Google Inc. Nexus Device (MTP)
#Bus 003 Device 004: ID 046d:0825 Logitech, Inc. Webcam C270
#Bus 003 Device 002: ID 0424:2412 Standard Microsystems Corp. 
#Bus 003 Device 008: ID 413c:2110 Dell Computer Corp. 
#Bus 003 Device 007: ID 046d:c52b Logitech, Inc. Unifying Receiver
#Bus 003 Device 006: ID 413c:1010 Dell Computer Corp. 
#Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub

file=File.join(MD, ME+".json")
$log.debug "file=#{file} LD=#{LD}"
class LsUsb
	RE_ENTRY=/^Bus\s(?<bus>\d+)\sDevice\s(?<device>\d+):\sID\s(?<id>\w+:\w+)\s(?<desc>.*)$/

	attr_reader :data, :changed, :empty
	def initialize
		@data={}  # loaded data
		@sdata={} # scanned data
		@changed=false
		@empty=false
	end

	def read(file)
		json=File.read(file)
	rescue Errno::ENOENT => e
		json="{}"
		$log.warn "empty data file detected: #{file}"
		@changed=true
	rescue => e
		$log.die "failed to read data file #{file}: #{e.to_s}"
	ensure
		return json
	end

	def parse_json(json)
		data=JSON.parse(json)
		@empty=data.empty?
		data
	rescue => e
		$log.die "failed to parse json: #{e.to_s} [#{json}]"
	end

	def load(file)
		json=read(file)
		@data=parse_json(json)
	end

	def make_key(desc, bus, device, id)
		"#{bus}_#{device}_#{desc.gsub(/\s/, "_")}"
	end

	def scan
		lines=%x/lsusb/.split(/\n/)
		@sdata={}
		lines.each { |line|
			line.strip!
			next if line.empty?

			m=line.match(RE_ENTRY)
			$log.die "failed to match input [#{line}]" if m.nil?

			id=m[:id].strip
			bus=m[:bus].strip
			device=m[:device].strip
			desc=m[:desc].strip
			$log.debug "Bus #{bus} Device #{device} ID #{id} #{desc}"

			dkey=make_key(desc, bus, device, id)
			h={
				:bus=>bus,
				:device=>device,
				:id=>id,
				:desc=>desc
			}
			@sdata[dkey]=h
		}
	end

	def compare
		@sdata.each_pair { |dkey, h|
			if @empty
				$log.info "Initializing #{dkey}=#{h.inspect}"
				@data[dkey]=h
				next
			end
			unless @data.key?(dkey)
				$log.warn "USB device detected [#{dkey}]\n#{h.inspect}"
				@changed=true
				next
			end
			[:bus, :device, :id, :desc].each { |key|
				next if @data[dkey][key.to_s].eql?(h[key])
				$log.warn "USB device change #{dkey}: %s != %s" % [ @data[dkey][key.to_s], h[key] ]
				@changed=true
			}
		}

		@data.each_pair { |dkey, h|
			unless @sdata.key?(dkey)
				$log.warn "USB device missing [#{dkey}]\n#{h.inspect}"
				@changed=true
				next
			end
			[:bus, :device, :id, :desc].each { |key|
				next if @sdata[dkey][key.to_s].eql?(h[key])
				$log.warn "USB device change #{dkey}: %s != %s" % [ @sdata[dkey][key.to_s], h[key] ]
				@changed=true
			}

		}

	end

	def save(file)
		File.open(file, "w") { |fd|
			json=JSON.pretty_generate(@data)
			$log.debug json
			fd.puts json
		}
	rescue => e
		$log.die "Failed to save data file #{file}"
	end
end

lsusb=LsUsb.new
lsusb.load(file)
lsusb.scan
lsusb.compare

$log.debug lsusb.data.inspect
if lsusb.changed
	$log.warn "USB data change detected"
	lsusb.save(file) if update
	exit 1
else
	$log.info "No change in data"
end
