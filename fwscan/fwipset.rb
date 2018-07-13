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

	def self.compare_fwscan_abuseipdb(entries, results, stream, opts)
		# no ipset name specified
		return if opts[:ipset].nil?

		vipset = FWipset.load_ipset(opts[:ipset], opts[:ssh])
		updated=false
		entries.each_pair { |ip, entrya|
			result = results[ip]
			next if result.nil? || result[:raw].nil?
			reports = result[:raw].count

			loc=IP2Location.lookup(ip)
			ip2loc_country = IP2Location.long(loc)
			ip2loc_isoCode = IP2Location.short(loc)

			if entrya.count > 2 && reports > 0 || reports >= 10
				if !FWipset.exists?(ip, opts[:ipset], opts[:ssh])
					stream.puts "Add to ipset #{opts[:ipset]}: #{ip} - #{ip2loc_isoCode} (#{ip2loc_country})"
					stream.puts FWipset.add(ip, opts[:ipset], opts[:ssh])
					updated=true
				end
			end
			if entrya.count >= 5 || reports > 10
				stream.puts "AbuseIPDB: reporting #{ip} - #{ip2loc_isoCode} (#{ip2loc_country})"
				# TODO summarise ports for array of fwlog entries
				comment=""
				entrya.each { |entry|
					comment += entry.ts_dpt_proto+"\n"
				}
				# TODO report to abuseipdb automatically
				# https://www.abuseipdb.com/report/json?key=[API_KEY]&category=[CATEGORIES]&comment=[COMMENT]&ip=[IP]
				# category=14
				# [IP]	Yes	NA	8.8.8.8 ::1	IPv4 or IPv6 Address
				# [DAYS]	No	30	30	Check for IP Reports in the last 30 days
				# [API_KEY]	Yes	NA	Tzmp1...quWvaiO	Your API Key (Get an API Key)
				# [CATEGORIES]	Yes	NA	10,12,15	Comma delineated list of category IDs (See all Categories)
				# [COMMENT]	No	blank	Brute forcing Wordpress login	Describe the type of malicious activity
				# [CIDR]	Yes	NA	207.126.144.0/20	IPv4 Address Block in CIDR notation
				# verbose flag	No	FALSE	/json?key=[API_KEY]&days=[DAYS]&verbose	When set, reports will include the comment (if any) and the reporter's user id number (0 if reported anonymously)
				result = AbuseIPDB.report(ip, [ AbuseIPDB::CATEGORIES[:PORT_SCAN], AbuseIPDB::CATEGORIES[:HACKING]], comment, {:stream=>stream})
				if !result[:error].nil?
					stream.puts "Failed to report #{ip}: "+result[:error]
				else
					stream.puts result.to_json
				end
				sleep opts[:sleep_secs]||2

			end
		}

		stream.puts " #{opts[:ipset]} ipset Summary ".center(50, "+")
		vipset.each_pair { |ip, fwipset|
			stream.puts fwipset.to_s
		}
		if updated
			cmd="shorewall save"
			cmd=ssh_cmd(cmd, opts[:ssh])
			stream.puts %x/#{cmd}/
		end
	end

end

#vipset = FWipset.load_ipset("badguys", "valium")
#puts JSON.pretty_generate(vipset)
#ip="185.255.31.80"
#puts FWipset.add(ip, "badguys", "valium")
#puts JSON.pretty_generate(vipset)
