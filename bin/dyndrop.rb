#!/usr/bin/env ruby

# http://www.ip2location.com/free/visitor-blocker

require 'optparse'
require 'logger'
require 'netaddr'
require 'readline'
require 'json'


ME=File.basename($0, ".rb")
MD=File.dirname(File.expand_path($0))
HOSTNAME=%x/hostname -s/

begin
	SHOREWALL_BIN=ENV['SHOREWALL_BIN']||%x/bash -c "type -p shorewall"/.strip
	#puts "bin="+SHOREWALL_BIN
	SHOREWALL_VER=%x/#{SHOREWALL_BIN} version/.strip
	#puts SHOREWALL_VER
	m=SHOREWALL_VER.match(/^(?<major>[5-])\.(?<minor>.*)/)
	raise "Valid shorewall version not found: #{SHOREWALL_VER}" if m.nil?
	puts "Detected #{SHOREWALL_BIN} version=#{m[:major]}.#{m[:minor]}"
rescue => e
	e.backtrace.each { |line|
		puts line
	}
	puts "shorewall: "+e.message
	puts "shorewall command not found or wrong version, faking it"

	SHOREWALL_BIN="echo shorewall"
	SHOREWALL_VER=""
end

puts "run #{SHOREWALL_BIN} blacklist CIDR"
puts "    #{SHOREWALL_BIN} show blacklists"
puts "    #{SHOREWALL_BIN} [safe-]restart"

class Logger
	def die(msg)
		self.error(msg)
		exit 1
	end
end

def set_logger(stream)
	$log = Logger.new(stream)
	$log.level = Logger::INFO
	$log.datetime_format = "%Y-%m-%d %H:%M:%S"
	$log.formatter = proc do |severity, datetime, progname, msg|
		"#{severity} #{datetime}: #{msg}\n"
	end
end

set_logger(STDERR)

$opts = {
	:addr=>nil,
	:range=>nil,
	:force=>false,
	:list=>false,
	:save=>false,
	:shell=>false,
	:global=>{},
	:cidr=>[],
	:history=>File.join(MD, ME+".history")
}

optparser = OptionParser.new do |opts|
	opts.banner = "#{ME}.rb [options]"

	opts.on('-D', '--debug', "Debug") {
		$log.level = Logger::DEBUG
	}

	opts.on('-s', '--[no-]shell', "Open shell") { |shell|
		$opts[:shell]=shell
	}

	opts.on('-a', '--addr ADDRESS', "IP address to lookup for range") { |addr|
		$opts[:addr]=addr
	}

	opts.on('-r', '--range RANGE', "IP address range to block") { |range|
		$opts[:range]=range
		#range.split(/\s*-\s*/)
	}

	opts.on('-c', '--cidr CIDR', "IP address range cidr (eg., 223.64.0.0/11)") { |cidr|
		$opts[:cidr] << cidr
	}

	opts.on('-l', '--list', "List dynamically dropped CIDRs") {
		$opts[:list]=true
	}

	opts.on('-f', '--force', "Don't prompt to drop cidr, just do it") {
		$opts[:force]=true
	}

	opts.on('-q', '--quiet', "Be quiet regarding console output") {
		$log.level = Logger::ERROR
	}

	opts.on('-h', '--help', "Help") {
		puts opts
		exit 0
	}
end
optparser.parse!

#Shorewall 5.1.10.2 blacklist chains at - Thu Feb 15 11:09:50 EST 2018
#
#Dynamic:
#5.188.11.0/24 timeout 0 packets 1130 bytes 45200
#77.72.85.0/24 timeout 0 packets 4150 bytes 166000
#...
#

def print_table(table)
	#sorted_ips = ips.sort_by { |ip| ip.split(".").map(&:to_i) }
	sorted_ips = table.keys.sort_by { |ip| ip.split(/[\.\/]/).map(&:to_i) }
	sorted_ips.each { |range|
		fields=table[range]
		# fields example
		# timeout 0 packets 65 bytes 2600
		puts "%20s: timeout %d packets %8d bytes %8d" % [ range, fields[1], fields[3], fields[5] ]
	}
end

def separator(print=true, len=80, ch='+')
	puts ch*len if print
end

def scanDynamic(print, output=nil)
	output=%x/#{SHOREWALL_BIN} show blacklists/ if output.nil?

	separator(print, 50, '+')

	scanning=false
	table={}
	output.each_line { |line|
		line.strip!
		#5.188.11.0/24 timeout 0 packets 1130 bytes 45200
		fields=line.split(/\s+/)
		if scanning
			if line.empty?
				scanning=false
				# print table now
				print_table(table) if print
			else
				if fields.length != 7
					$log.warn "Unexpected input, expecting 7 WS delimited fields: [#{line}]"
				else
					range,ltimeout,timeout,lpackets,packets,lbytes,bytes=fields
					if table.key?(range)
						$log.warn "Duplicate range found, ignoring: #{line}"
					else
						fields.delete_at(0)
						table[range]=fields
					end
				end
			end
		elsif fields.length == 1 && fields[0][/^Dynamic:/].nil? == false
			puts line if print
			scanning=true
		else
			puts line if print
		end
	}
	if scanning
			$log.warn "End of dynamic range table not found"
			print_table(table) if print
	end

	separator(print, 50, '+')

	return table
end

unless $opts[:addr].nil?
begin
	puts %x/whois #{$opts[:addr]}/
	while true
		ans=Readline.readline("Enter range x.x.x.x-y.y.y.y> ", false).strip
		if ans[/\d+\.\d+\.\d+\.\d+\s*-\s*\d+\.\d+\.\d+\.\d+/]
			$opts[:range]=ans
			break
		elsif ans[/\d+\.\d+\.\d+\.\d+\/\d+/]
			$opts[:cidr] << ans
			break
		else
			$log.error "Invalid input: #{ans}"
		end
	end
rescue Interrupt => e
	$log.die "Caught interrupt: "+e.to_s
end
end

BINARY_H={}
(0..255).each { |v| BINARY_H[v]="%08b"%v }
BITSHIFT_TABLE={
	0=>0b00000001,
	1=>0b10000000,
	2=>0b01000000,
	3=>0b00100000,
	4=>0b00010000,
	5=>0b00001000,
	6=>0b00000100,
	7=>0b00000010
}

RE_ADDR=/(addr\s*)?(?<a>\d+\.\d+\.\d+\.\d+)/
RE_RANGE=/(range\s*)?(?<r1>\d+\.\d+\.\d+\.\d+)\s*-\s*(?<r2>\d+\.\d+\.\d+\.\d+)/
RE_CIDR=/(cidr\s*)?(?<a1>\d+)(?<a2>\.\d+)?(?<a3>\.\d+)?(?<a4>\.\d+)?\/(?<mask>\d+)(?:\s|$)/
RE_QUIT=/(quit|exit)/
RE_SHOW=/(show)/
RE_SAVE=/(save)/
RE_HAS=/(has)\s+(?<a>.*)/
RE_HELP=/(help)/
RE_EMACS=/(emacs)/
RE_VI=/(vim?)/
RE_GLOBAL=/(?<key>addr|range|cidr)$/
RE_GLOBALS=/(globals)/
RE_HISTORY=/(history)/

HELP_TEXT=<<-HELPTEXT
	Commands  Description
	--------  -----------------------------------------------------
	range     ip address range (a.b.c.d - a.b.c d)
	cidr      cidr (a.b.c.d/mask)
	addr      ip address (run whois to discover range or cidr)
	show      show dynamic
	save      save shorewall state
	has       search for ip address
	globals   list known global variables
	quit      quit shell
	emacs     use emacs command line editing
	vi|vim    user vi command line editing
	help      this help text

	The range, cidr and addr command strings are optional, meaning that it
	will automatically detect ranges, cidrs or ipv4 addresses

HELPTEXT

def helptext
	# no <<~ on ruby 2.[012]
	HELP_TEXT.split(/\n/).map { |line| line.strip }.join("\n")
end

RE_IPV4=/(?<a1>\d+)\.(?<a2>\d+)\.(?<a3>\d+)\.(?<a4>\d+)/
def ipv4_to_a(addr)
	a=[]
	m=RE_IPV4.match(addr)
	unless m.nil?
		[ :a1, :a2, :a3, :a4 ].each { |name|
			a << m[name].to_i
		}
	end
	a
end

def match2range(m, ret)
	ret[:range]=m[:r1]+"-"+m[:r2]
	ret[:lower]=m[:r1]
	ret[:upper]=m[:r2]
	ret
end

def match2cidr(m, ret)
	cidr  = m[:a1]
	cidr += m[:a2]||".0"
	cidr += m[:a3]||".0"
	cidr += m[:a4]||".0"
	cidr += "/"
	cidr += m[:mask]
	ret[:cidr]=cidr
	ret
end

def match2addr(m, ret)
	ret[:addr]=m[:a]
	ret
end

#
# run whois on addr, parse out RANGE or CIDR from output, store in data hash
#
# :out    - full output
# :range  - range from output if found
#  :lower  - lower addr from range
#  :upper  - upper addr from range
# :cidr   - cidr from output if found
#

RE_COUNTRY=/country:\s*(?<country>.*)?$/i
RE_ADDRESS=/address:\s*(?<address>.*)?$/i
def whois_parser(addr, whois_opts="")
begin
	data={}
	out=%x/whois #{whois_opts} #{addr}/
	data[:out]=out
	m=nil
	begin
		m=RE_RANGE.match(out)
	rescue
		# take a stab at fixing the encoding
		data[:out]=out.encode('utf-8', 'iso-8859-1')
		out=data[:out]
		m=RE_RANGE.match(out)
	end
	unless m.nil?
		r=match2range(m, {})
		# add :range, :lower and :upper
		data.merge!(r)
	end
	m=RE_CIDR.match(out)
	unless m.nil?
		r=match2cidr(m, {})
		data[:cidr] = r[:cidr]
	end
	m=RE_COUNTRY.match(out)
	unless m.nil?
		data[:country]=m[:country]
	end
	a=out.scan(RE_ADDRESS)
	unless a.nil?
		data[:address]=a.flatten
	end
rescue => e
	puts e.message
	e.backtrace.each { |line|
		puts line
	}
ensure
	if !data.key?(:range) && whois_opts.empty?
		# no range found, let's try again using another server
		puts data[:out]
		return whois_parser(addr, " -n -h whois.apnic.net ")
	end
	return data
end
end

# resolve the type of address in ret hash with value stored in key
# types are ipv4 range, cidr or addr
def get_key_address(ret, key)
	a=ret[key]

	puts "Matching addr #{a}"

	m=a.match(RE_RANGE)
	if m.nil?
		m=a.match(RE_CIDR)
		if m.nil?
			m=a.match(RE_ADDR)
			if m.nil?
				ret[:unknown] = "Unknown address format [#{a}]"
			else
				ret=match2addr(m, ret)
			end
		else
			ret=match2cidr(m, ret)
		end
	else
		ret=match2range(m, ret)
	end

	ret
end

def shell_cmd(opts)
	ret={}
	begin
		ans=Readline.readline("> ", true).strip
		return ret if ans.empty?

		m=ans.match(RE_EMACS)
		unless m.nil?
			puts "Switching to #{ans} editing mode"
			Readline.emacs_editing_mode
			return ret
		end
		m=ans.match(RE_VI)
		unless m.nil?
			puts "Switching to #{ans} editing mode"
			Readline.vi_editing_mode
			return ret
		end

		m=ans.match(RE_GLOBAL)
		unless m.nil?
			key=m[:key].to_sym
			val = get_global_key(key, opts)
			return ret if val.nil?
			puts opts[:global].inspect
			ret=get_key_address(opts[:global], key)
			return ret
		end

		case ans
		when RE_QUIT
			ret[:quit]=true
			return ret
		when RE_HELP
			ret[:help]=true
			return ret
		when RE_SHOW
			ret[:show]=true
			return ret
		when RE_SAVE
			ret[:save]=true
			return ret
		when RE_GLOBALS
			ret[:globals]=true
			return ret
		when RE_HISTORY
			ret[:history]=true
			return ret
		end

		m=ans.match(RE_HAS)
		unless m.nil?
			ret[:has]=m[:a]
			return get_key_address(ret, :has)
		end

		m=ans.match(RE_RANGE)
		return match2range(m, ret) unless m.nil?

		m=ans.match(RE_CIDR)
		return match2cidr(m, ret) unless m.nil?

		m=ans.match(RE_ADDR)
		return match2addr(m, ret) unless m.nil?

		ret[:unknown]=ans
	rescue Interrupt => e
		# ignore
	rescue => e
		ret[:error]=e
		e.backtrace.each { |line| puts line }
	end
	ret
end

def byte_2_bitstring(b)
	b = b.to_i
	raise "Byte out of range: #{b}\n" if b < 0 || b > 255
	BINARY_H[b]
end

def array_2_bitstring(a, sep=" ")
	bits=""
	a.each { |c|
		cbits = byte_2_bitstring(c)
		#puts "#{c}: #{cbits}"
		bits += cbits
		next if sep.nil? || sep.empty?
		bits += sep
	}
	bits
end

def printBits(a, suffix="", sep=" ")
	puts array_2_bitstring(a, sep).strip+suffix
rescue => e
	print e.to_s
end

def getNextCidr(la, ua, echo)
	xa=[]
	# xor each chunk lower ^ upper
	la.each_index { |i|
		#puts "la[#{i}]=#{la[i]} class=#{la[i].class}"
		xa << (la[i] ^ ua[i])
	}
	if echo
		printBits(la)
		printBits(ua)
		printBits(xa, " xor")
		puts "12345678 90123456 78901234 56789012"
		puts "          1          2          3"
	end

	# range 118.193.24.0-118.193.31.255
	# la 01110110 11000001 00011000 00000000
	# ua 01110110 11000001 00011111 11111111
	# xa 00000000 00000000 00000111 11111111 xor
	#    12345678 90123456 78901234 56789012
	#              1          2          3
	# 118.193.7.0/21 cidr
	#
	# Example with hole in xor (0 at bit 17) after first 1 (at bit 15)
	# ip0 00111010 00111000 00000000 00000000 58.56.0.0
	# ip1 00111010 00111011 01111111 11111111 58.59.127.255
	# xor 00000000 00000011 01111111 11111111 15th bit differs, 58.56.0.0/15
	#     12345678 90123456 78901234 56789012
	#               1          2          3
	#
	# For the next ip0, flip the 15th bit of the last ip0, and compare to ip1 again

	# hole is true if a 0 is found in xa after the first one is found
	hole = false
	found_one = false
	bitc0 = 0
	xxa=[]
	xa.each_with_index { |xv, i|
		if xv == 0
			# 8 zero bits in a 0 byte
			bitc0 += 8
			xxa << la[i]
		elsif xv == 255
			xxa << 0
		else
			xxa << la[i]
			xvs = "%08b" % xv
			xvs.each_char { |bit|
				if bit.eql?("1")
					found_one = true
				else
					# a 0 bit after a 1 has been found is a hole
					if found_one
						# found a zero bit after a 1, flag it as a hole
						hole = true
					else
						# found a zero bit before a 1, tally it
						bitc0 += 1
					end
				end
			}
		end
	}

	clean = !hole
	puts "Clean=#{clean} hole=#{hole} bitc0=#{bitc0}"
	if hole
		# found a zero after a one in xa, flip the next bit in la
		bitc0 += 1
		# 14 then octet is 1 and bitshift is 2 (1 << 2)
		# 15 then octet is 1 and bitshift is 1 (1 << 1)
		# 16 then octet is 1 and bitshift is 0 (1 << 0)
		# 17 then octet is 2 and bitshift is 7 (1 << 7)
		bitshift = bitc0 % 8
		# bitc0 | bitc0 % 8 | bitshift | 1 << bitshift
		# 8       0           8-0=0      0b00000001
		# 9       1           8-1=7      0b10000000
		# 10      2           8-2=6      0b01000000
		# 11      3           8-3=5      0b00100000
		# 12      4           8-4=4      0b00010000
		# 13      5           8-5=3      0b00001000
		# 14      6           8-6=2      0b00000100
		# 15      7           8-7=1      0b00000010
		# 16      0           8-0=0      0b00000001
		octet = bitc0 / 8 - (bitshift == 0 ? 1 : 0)

		puts "Before: octet=#{octet} bitshift=#{bitshift} la[octet]=#{byte_2_bitstring(la[octet])}"
		bit=BITSHIFT_TABLE[bitshift]
		la[octet] ^= bit
		puts "After: bit=#{byte_2_bitstring(bit)} la[octet]=#{byte_2_bitstring(la[octet])}"
	end
	# if all bits after the zero_bits are ones, the cidr is complete
	zero_bits = bitc0

	#abits = array_2_bitstring(xa, "")
	#abits.each_char.with_index { |bit, i|
	#	next if i < zero_bits
	#	next if bit.eql?("1")
	#	clean = false
	#	break
	#}

	cidr=xxa.join(".")+"/#{zero_bits}"
	puts "#{cidr} cidr #{clean}" if echo
	puts "" if echo
	#clean ? cidr : nil
	bits = clean ? zero_bits : zero_bits
	{
		:clean=>clean,
		:cidr=>cidr,
		:la=>la
	}
rescue => e
	puts ">>"+e.to_s
	e.backtrace.each { |x|
		puts ">>"+x
	}

end

def getCidrFromRange(lower, upper, cidrs, echo)
	puts "" if echo
	puts "Getting cidr for range #{lower}-#{upper}" if echo
	la=ipv4_to_a(lower)
	ua=ipv4_to_a(upper)

	maxLoops = 16
	curLoops = 0
	loop {
		res = getNextCidr(la, ua, echo)
		cidrs << res[:cidr]
		return cidrs if res[:clean]
		la = res[:la]
		curLoops += 1
		break if curLoops >= maxLoops
	}
	puts "Failed to get cidrs for range #{lower}-#{upper}"
	nil
end

def getMergedCidr(lower, upper, echo=true)
	cidrs = []
	cidrs = getCidrFromRange(lower, upper, cidrs, true)
	if cidrs.nil?
		puts "Getting range for #{lower}-#{upper}" if echo
		ip_net_range = NetAddr.range(lower, upper, :Inclusive => true, :Objectify => true)
		puts "Getting merged cidr array" if echo
		cidrs = NetAddr.merge(ip_net_range, :Objectify => true)
		GC.start
	end
	cidrs
rescue Interrupt => e
	puts "Interrupted "+e.to_s
	[]
end

def blackListCidr(cidr, opts)
	table = scanDynamic(false)
	if table.key?(cidr)
		puts "Cidr #{cidr} is already blacklisted"
		return
	end

	ans=$opts[:force]==true ? "y" : Readline.readline("Drop cidr #{cidr}? [y/n] ", false).strip.downcase
	if ans.eql?("y")
		puts "Dropping cidr=#{cidr}"
		puts %x/#{SHOREWALL_BIN} blacklist #{cidr}/
		opts[:save]=true
		opts[:list]=true
	end
end

def search_table_cidr(table, addr, cs)
	puts "Searching blacklist table for #{addr} in #{cs}"
	table.sort.to_h.each_pair { |key,val|
		#puts "#{cs} #{key} #{val}"
		return cs if key.eql?(cs)
	}
	nil
end

def search_table(table, addr, cidrs)
	dupes=[]
	blacklisted=[]
	cidrs.each { |cidr|
		cs=cidr.to_s
		next if dupes.include?(cs)
		dupes << cs
		out=search_table_cidr(table, addr, cs)
		next if out.nil?
		blacklisted << out
	}
	puts
	blacklisted.each { |cs|
		puts " ** Address #{addr} is blacklisted in #{cs}"
	}
end

def shell_history_load(opts)
	history=File.read(opts[:history])
	history.split(/\n/).each { |line|
		Readline::HISTORY.push(line)
	}
rescue => e
	$log.info "Failed to load history: "+e.to_s
end

def shell_history_save(opts)
	File.open(opts[:history], "w") { |fd|
		Readline::HISTORY.to_a.uniq.each { |line|
			fd.puts line
		}
	}
rescue => e
	$log.info "Failed to save history: "+e.to_s
end

def shell_history_show(opts)
	Readline::HISTORY.to_a.uniq.each { |line|
		line.strip!
		next if line.empty?
		puts line
	}
end

def shell_editing_mode
	editor=ENV['VISUAL']||ENV['EDITOR']
	case editor
	when RE_VI
		Readline.vi_editing_mode
	when RE_EMACS
		Readline.emacs_editing_mode
	else
	end
end

def shorewall_save(opts)
	puts %x/#{SHOREWALL_BIN} save/
	opts[:save]=false
end

def set_global_key(key, data, opts)
	val=data[key]
	return if val.nil?
	opts[:global][key]=val
	puts "%10s: %s" % [key.to_s.capitalize, val ]
end

def get_global_key(key, opts)
	return nil if opts[:global].nil?
	return opts[:global][key]
end

def has_address(ret, key, opts, echo=true)
	cidrs = []
	addr=ret[key]
	table = scanDynamic(false)
	if ret.key?(:range)
		cidrs.concat(getMergedCidr(ret[:lower], ret[:upper], echo))
	elsif ret.key?(:cidr)
		cidrs << ret[:cidr]
	elsif ret.key?(:addr)
		data=whois_parser(ret[:addr])
		if data[:range].nil? && data[:cidr].nil?
			puts data[:out] if echo
		else
			if data.key?(:range)
				puts "Range: "+data[:range] if echo
				set_global_key(:range, data, opts)
				cidrs.concat(getMergedCidr(data[:lower], data[:upper], echo))
			end
			if data.key?(:cidr)
				puts " CIDR: "+data[:cidr] if echo
				cidrs << data[:cidr]
			end
		end
	elsif ret.key?(:unknown)
		puts ret.inspect
	else
		puts "Shouldn't get here"
	end
	search_table(table, addr, cidrs)
end


def shell_run(opts)
	shell_history_load(opts)
	shell_editing_mode
	puts helptext
	while true
		ret=shell_cmd(opts)
		if ret[:quit]
			puts "Quitting"
			break
		elsif ret[:show]
		    scanDynamic(true)
		elsif ret[:save]
			$opts[:save]=true
			shorewall_save(opts)
		elsif ret[:has]
			has_address(ret, :has, opts)
		elsif ret[:addr]
			puts ret[:addr]
			data=whois_parser(ret[:addr])
			puts data[:out]

			set_global_key(:addr, data, opts)
			set_global_key(:range, data, opts)
			set_global_key(:cidr, data, opts)
			set_global_key(:county, data, opts)

			data[:address].each { |address|
				puts "%10s: %s" % [ "Address", address ]
			} if data.key?(:address)

			puts

			ret = get_key_address(ret, :addr)
			has_address(ret, :addr, opts, false)

			puts

		elsif ret[:range]
			puts ret[:range]
			cidrs=getMergedCidr(ret[:lower], ret[:upper], true)
			cidrs.each { |cidr|
				blackListCidr(cidr, opts)
			}
		elsif ret[:cidr]
			puts ret[:cidr]
			blackListCidr(ret[:cidr], opts)
		elsif ret[:globals]
			opts[:global].each_pair { |key, val|
				puts "%8s: %s" % [ key.to_s.capitalize, val ]
			}
		elsif ret[:history]
			shell_history_show(opts)
		elsif ret[:error]
			puts ret[:error]
		elsif ret[:unknown]
			puts "Unrecognized input: "+ret[:unknown]
		elsif ret[:help]
			puts helptext
		else
			puts
		end
	end
	shell_history_save(opts)
rescue => e
	e.backtrace.each { |line| puts line }
end

shell_run($opts) if $opts[:shell]

unless $opts[:range].nil?
	$log.die "No range found" if $opts[:range].nil?
	$log.die "Aborting" if $opts[:range].empty?

	$opts[:range]=$opts[:range].split(/\s*-\s*/)
	$log.die "Invalid range class=#{$opts[:range].class}" unless $opts[:range].class == Array
	$log.die "Invalid range array size #{$opts[:range].size}" unless $opts[:range].size == 2

	lower=$opts[:range][0]
	upper=$opts[:range][1]
	$log.info "Getting range for #{lower}-#{upper}"
	ip_net_range = NetAddr.range(lower, upper, :Inclusive => true, :Objectify => true)
	$log.info "Getting merged cidr array"
	cidrs = NetAddr.merge(ip_net_range, :Objectify => true)
	$opts[:cidr].concat(cidrs)
end

$opts[:cidr].each { |cidr|
	ans=$opts[:force]==true ? "y" : Readline.readline("Drop cidr #{cidr}? [y/n] ", false).strip.downcase
	if ans.eql?("y")
		puts "Dropping cidr=#{cidr}"
		puts %x/#{SHOREWALL_BIN} blacklist #{cidr}/
		$opts[:save]=true
		$opts[:list]=true
	else
		$log.warn "Skipping cidr=#{cidr}"
		$opts[:cidr].delete(cidr)
	end
}

shorewall_save($opts) if $opts[:save]

if $opts[:list]
	output=%x/#{SHOREWALL_BIN} show blacklists/
	scanDynamic(true, output)
end

$opts[:cidr].each { |cidr|
	puts "Dropped cidr=#{cidr}"
}
