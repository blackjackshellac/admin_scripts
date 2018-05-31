#!/usr/bin/env ruby
#

require 'json'
require 'logger'

class FWipset
	# 3600*24*30 = 86400*30 = 2592000 (30 days is too big, value overflows in kernel)
	#  >>> https://marc.info/?l=netfilter-devel&m=141351695203549&w=2
	# max timeout is 2147483 seconds [(UINT_MAX/1000)/2] which is about 24.855127315 days
	# ipset create badguys hash:ip timeout 2147483 counters
	# ipset list
	# ipset add badguys 108.178.59.35
	# ipset add badguys 69.175.42.144
	# ipset list badguys

	# 69.175.42.144 timeout 2135761 packets 0 bytes 0
	RE_ENTRY=/(?<ip>\d+\.\d+\.\d+\.\d+)\stimeout\s(?<timeout>\d+)\spackets\s(?<packets>\d+)\sbytes\s(?<bytes>\d+)/
	IPSETS=Hash.new { |hash, key| hash[key]={} }

	@@log = Logger.new(STDOUT)

	attr_reader :ip, :timeout, :packets, :bytes
	def initialize(ip, timeout, packets, bytes)
		@ip = ip
		@timeout = timeout
		@packets = packets
		@bytes = bytes
	end

	def self.init(opts)
		@@log = opts[:logger]
		raise "Logger not set in FWLog" if @@log.nil?
	end

	def self.from_match(m)
		m.nil? ? nil : FWipset.new(m[:ip], m[:timeout], m[:packets], m[:bytes])
	end

	def self.from_line(line)
		line.strip!
		m=RE_ENTRY.match(line)
		from_match(RE_ENTRY.match(line))
	end

	def self.ipset_key(setname, host)
		host="localhost" if host.nil?
		"#{host}_#{setname}"
	end

	def self.get_ipset(setname, host)
		IPSETS[ipset_key(setname, host)]
	end

	def self.ssh_cmd(cmd, host)
		host="localhost" if host.nil?
		"ssh root@#{host} #{cmd}"
	end

	def self.load_ipset(setname, host=nil)
		cmd="ipset list #{setname}"
		cmd=ssh_cmd(cmd, host)

		ipset=get_ipset(setname, host)

		puts cmd
		out=%x/#{cmd}/
		out.split(/\n/).each { |line|
			entry=from_line(line)
			next if entry.nil?
			ipset[entry.ip]=entry
		}
		ipset
	end

	def to_s
		"%15s timeout=%d packets=%d bytes=%d" % self.to_a
	end

	def to_a
		[ @ip, @timeout, @packets, @bytes ]
	end

	def to_json(*a)
		as_json.to_json(*a)
	end

	def as_json
		{
			:timeout=>@timeout,
			:packets=>@packets,
			:bytes=>@bytes
		}
	end

	def self.exists?(ip, setname, host=nil)
		ipset=get_ipset(setname, host)
		ipset.key?(ip)
	end

	def self.add(ip, setname, host=nil)
		ipset=get_ipset(setname, host)
		return " >> IP already in ipset #{ip}" if ipset.key?(ip)
		cmd="ipset add #{setname} #{ip}"
		cmd=ssh_cmd(cmd, host)
		out=%x/#{cmd}/
		out.strip
	end
end

#vipset = FWipset.load_ipset("badguys", "valium")
#puts JSON.pretty_generate(vipset)
#ip="185.255.31.80"
#puts FWipset.add(ip, "badguys", "valium")
#puts JSON.pretty_generate(vipset)
