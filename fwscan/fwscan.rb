#!/usr/bin/env ruby
#

require 'time'
require 'json'
require 'fileutils'
require 'find'
require 'csv'
require 'open3'
require 'tempfile'

me=File.symlink?($0) ? File.readlink($0) : $0
ME=File.basename($0, ".rb")
MD=File.realpath(File.dirname(me))
LIB=File.realpath(File.join(MD, "..", "lib"))

#puts "ME="+ME
#puts "MD="+MD
#puts "LIB="+LIB

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")
require_relative File.join(MD, "fwlog")
require_relative File.join(MD, "format_xlsx")
#require_relative File.join(LIB, "whois_classifier", "whois_bayes")
require_relative File.join(MD, "abuseipdb")
require_relative File.join(MD, "emailer")
require_relative File.join(MD, "fwipset")

$log=Logger.set_logger(STDERR, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

FORMATS=[ :json, :xlsx, :csv ]

$opts={
	:since=>nil,
	:until=>nil,
	:ssh=>nil,
	:file=>nil,
	:filter=>/Shorewall:/,
	:in=>"enp2s0",
	:format=>:json,
	:name=>File.join(TMP,ME+"_output"),
	:label=>nil,
	:force=>false,
	:resolv=>false,
	:lookup=>false,
	:logger=>$log,
	:headers=>true,
	:ipdb_apikey=>nil,
	:email=>nil,
	:ipset=>nil
}

$opts = OParser.parse($opts, "") { |opts|
	# journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"

	opts.on('-K', '--filter FILTER', String, "Kernel log filter string, default #{$opts[:filter]}") { |filter|
		filter.strip!
		filter = filter.empty? ? nil : /#{filter}/
		$opts[:filter]=filter
	}

	opts.on('-k', '--since DATE', String, "Kernel log since YYYY-mm-dd HH:MM:SS, or integer seconds before 'now'") { |since|
		if since.to_i > 0
			ts=Time.now.to_i-since.to_i
			since=Time.at(ts).strftime("%Y-%m-%d %H:%M:%S")
		end
		$opts[:since]=since
	}

	opts.on('-u', '--until DATE', String, "Kernel log until YYYY-mm-dd HH:MM:SS, defaults to now") { |duntil|
		$opts[:until]=duntil
	}

	opts.on('-S', '--ssh USER_HOST', String, "ssh to user@host to run journalctl") { |user_host|
		$opts[:ssh]=user_host
	}

	opts.on('-c', '--check KEY', String, "API key for AbuseIPDB") { |apikey|
		#https://www.abuseipdb.com/check/[IP]/json?key=[API_KEY]&days=[DAYS]
		$opts[:ipdb_apikey]=apikey
	}

	opts.on('-e', '--email ADDRESS', String, "Recipient for fwscan summary") { |email|
		$opts[:email]=email
		$opts[:subject]="%s: fwscan summary %s" % [ %x/hostname -s/.strip, Time.now.strftime('%Y%m%d-%H%M') ]
	}

	opts.on('-i', '--input FILE', String, "Kernel log to parse") { |file|
		$opts[:file]=file
	}

	opts.on('-I', '--in NET_DEV', String, "Network device, default=#{$opts[:in]}") { |inp|
		$opts[:in]=inp
	}

	opts.on('-P', '--ipset NAME', String, "ipset name on firewall to block ips dynamically") { |name|
		$opts[:ipset]=name
	}

	opts.on('-f', '--format FORMAT', String, "Output format: #{FORMATS.to_json}") { |type|
		format = type.downcase.to_sym
		format = nil unless FORMATS.include?(format)
		$log.die "Unknown output format: #{type}" if format.nil?
		$opts[:format]=format
	}

	opts.on('-o', '--output FILE', String, "Output filename, use - for stdout") { |name|
		$opts[:name]=name
	}

	opts.on('-F', '--[no-]force', "Force overwrite of output file") { |force|
		$opts[:force]=force
	}

	opts.on('-R', '--[no-]resolve', "Resolve hostnames of src IP addresses") { |resolv|
		$opts[:resolv]=resolv
	}

	opts.on('-L', '--[no-]lookup', "Lookup service name") { |lookup|
		$opts[:lookup]=lookup
	}

	opts.on('--[no-]headers', "Disable headers, default=#{$opts[:headers]}") { |headers|
		$opts[:headers]=headers
	}
}
$opts[:in]=/IN=#{$opts[:in]}\s/

$log.die "Must specify an input file (--file) or time since (--since)" if $opts[:file].nil? && $opts[:since].nil?

FWLog.init($opts)
AbuseIPDB.init($opts)
Emailer.init($opts)
FWipset.init($opts)

input=[]
if !$opts[:file].nil?
	File.open($opts[:file], "r") { |fd|
		fd.each { |line|
			line = FWLog.filter(line, $opts)
			input << line unless line.nil?
		}
	}
elsif !$opts[:since].nil?
	#journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"
	ssh=$opts[:ssh]
	cmd=""
	cmd  = %Q/ssh #{ssh} '/ unless ssh.nil?
	cmd += %Q/journalctl -k --since "#{$opts[:since]}"/
	cmd += %Q/ --until "#{$opts[:until]}"/ unless $opts[:until].nil?
	cmd += %Q/'/ unless ssh.nil?
	$log.info cmd
	Open3.popen3(cmd) { |sin,sout,serr,thr|
		pid=thr.pid
		sout.each { |line|
			$log.debug ">> "+line
			line = FWLog.filter(line, $opts)
			input << line unless line.nil?
		}
		status=thr.value
		if status != 0
			serr.each { |line|
				$log.error line.chomp
			}
			$log.die "Process #{pid} exited with status #{status}"
		end
		$log.info "Process #{pid} exited with status #{status}"
	}
end

ts_min=nil
ts_max=nil
entries={}
input.each { |line|
	e = FWLog.parse(line, $opts)
	next if e.nil?
	entries[e.src] ||= []
	entries[e.src] << e
	ts = e.ts
	ts_min = ts if ts_min.nil? || ts_min > ts
	ts_max = ts if ts_max.nil? || ts_max < ts
}

$log.die "Nothing to output, firewall journal entries is empty" if entries.empty?

case $opts[:format]
when :xlsx
	FormatXLSX.init($opts)
	begin
		output_name = FWLog.output_name($opts[:name], ts_min, ts_max, ".xlsx")
		fxlsx = FormatXLSX.new(output_name, $opts[:label], $opts)
	rescue => e
		$log.die "Failed to create xlsx object: #{e}"
	end
	row=0
	row = fxlsx.write_headers(row, 0, FWLog.to_a_headers)
	entries.each_pair { |src,fwla|
		n=0
		fwla.each { |fwl|
			row = fxlsx.write_row(row, 0, fwl.to_a(:n=>n))
			n+=1
		}
	}
	fxlsx.close
when :csv
	output_name = FWLog.output_name($opts[:name], ts_min, ts_max, ".csv")
	$log.die "File exists: #{output_name}" if File.exists?(output_name) && !$opts[:force]
	$log.info "Writing #{output_name}"
	fd = output_name.eql?("-") ? $stdout : File.open(output_name, "w")
	csv = CSV.new(fd)
	csv << FWLog.to_a_headers if $opts[:headers]
	entries.each_pair { |src,fwla|
		fwla.each { |fwl|
			# set :n to 0 to print every :src row
			csv << fwl.to_a(:n=>0)
		}
	}
	csv.close
	fd.close
when :json
	#result = []
	#entries.each_pair { |src, fwla|
	#	fwla.each { |fwl|
	#		result << fwl.to_a
	#	}
	#}
	#puts JSON.pretty_generate(result)
	#puts JSON.pretty_generate(entries)
else
	puts "No output format specified"
end

#result = AbuseIPDB.check("37.72.175.156")
#entries = {}
#AbuseIPDB.summarise_result(result)

vipset = FWipset.load_ipset($opts[:ipset], $opts[:ssh]) unless $opts[:ipset].nil?

errors=0
results={}
entries.each_pair { |ip, entry|
	sleep 0.25
	result = AbuseIPDB.check(ip)
	next if result.empty?

	unless result[:error].nil?
		$log.error result[:error]
		errors += 1
		# just give up
		break if errors >= 10
		sleep 10
	end

	results[ip]=result

} unless $opts[:ipdb_apikey].nil?

Tempfile.open('fwscan') { |stream|
	# summarise ip and counts
	FWLog.summarise_entries(entries, results, stream)

	# allow entries to access counts
	$opts[:entries]=entries
	AbuseIPDB.summarise_results(results, stream, $opts)

	unless $opts[:ipset].nil?
		updated=false
		entries.each_pair { |ip, entry|
			result = results[ip]
			next if result[:raw].nil?
			if entry.count > 2 && result[:raw].count > 2
				stream.puts "Block ip #{ip} in #{$opts[:ipset]}"
				stream.puts FWipset.add(ip, $opts[:ipset], $opts[:ssh])
				updated=true
			end
		}

		stream.puts " #{$opts[:ipset]} ipset Summary ".center(50, "+")
		vipset.each_pair { |ip, fwipset|
			stream.puts fwipset.to_s
		}
		if updated
			cmd=$opts[:ssh].nil? ? "" : "ssh root@#{$opts[:ssh]} "
			cmd="#{cmd}shorewall save"
			stream.puts %x/#{cmd}/
		end
	end

	stream.rewind
	if $opts[:email].nil?
		puts stream.read
	else
		$opts[:body]=stream.read
		$opts[:email_to]=$opts[:email]
		$opts[:email_from]=$opts[:email]

		Emailer.mail($opts)
	end


}
