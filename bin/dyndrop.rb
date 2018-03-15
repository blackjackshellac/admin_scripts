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
	SHOREWALL_BIN=%x/bash -c "type -p shorewall"/.strip
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
	puts "shorewall command not found or wrong version"

	exit 1
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
	:cidr=>[]
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

RE_ADDR=/(addr\s*)?(?<a>\d+\.\d+\.\d+\.\d+)/
RE_RANGE=/(range\s*)?(?<r1>\d+\.\d+\.\d+\.\d+)\s*-\s*(?<r2>\d+\.\d+\.\d+\.\d+)/
RE_CIDR=/(cidr\s*)?(?<a1>\d+)(?<a2>\.\d+)?(?<a3>\.\d+)?(?<a4>\.\d+)?\/(?<mask>\d+)/
RE_QUIT=/(quit|exit)/
RE_SHOW=/(show)/
RE_SAVE=/(save)/
RE_HAS=/(has)\s+(?<a>.*)/
RE_HELP=/(help)/
RE_EMACS=/(emacs)/
RE_VI=/(vim?)/
RE_GLOBAL=/(?<key>range|cidr)/

HELP_TEXT=<<-HELPTEXT
	Commands  Description
	--------  -----------------------------------------------------
	range     ip address range (a.b.c.d - a.b.c d)
	cidr      cidr (a.b.c.d/mask)
	addr      ip address (run whois to discover range or cidr)
	show      show dynamic
	save      save shorewall state
	has       search for ip address
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
def whois_parser(addr)
begin
	data={}
	out=%x/whois #{addr}/
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
	return data
end
end

# resolve the type of address in ret hash with value stored in key
# types are ipv4 range, cidr or addr
def get_key_address(ret, key)
	a=ret[key]

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
			return nil if val.nil?
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
		ret[:quit]=true
	rescue => e
		ret[:error]=e
	end
	ret
end

def getMergedCidr(lower, upper, echo=true)
	puts "Getting range for #{lower}-#{upper}" if echo
	ip_net_range = NetAddr.range(lower, upper, :Inclusive => true, :Objectify => true)
	puts "Getting merged cidr array" if echo
	cidrs = NetAddr.merge(ip_net_range, :Objectify => true)
	cidrs
end

def blackListCidr(cidr, opts)
	ans=$opts[:force]==true ? "y" : Readline.readline("Drop cidr #{cidr}? [y/n] ", false).strip.downcase
	if ans.eql?("y")
		puts "Dropping cidr=#{cidr}"
		puts %x/#{SHOREWALL_BIN} blacklist #{cidr}/
		opts[:save]=true
		opts[:list]=true
	end
end

def search_table(table, addr, cidrs)
	found=false
	dupes=[]
	cidrs.each { |cidr|
		cs=cidr.to_s
		next if dupes.include?(cs)
		puts "Searching for #{addr} in blacklisted cidr #{cs}"
		table.each_pair { |key,val|
			if key.eql?(cs) 
				puts "Address #{addr} is blacklisted in #{cs}"
				found=true
				dupes << cs
			end
		}
		puts "cidr #{cs} not blacklisted" unless found
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
	opts[:global]||={}
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
				blackListCidr(cidr, $opts)
			}
		elsif ret[:cidr]
			puts ret[:cidr]
			blackListCidr(ret[:cidr], $opts)
		elsif ret[:error]
			puts ret[:error]
		elsif ret[:unknown]
			puts "Unrecognized input: "+ret[:unknown]
		elsif ret[:help]
			puts helptext
		else
		end
	end

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

