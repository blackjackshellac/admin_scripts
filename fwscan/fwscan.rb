#!/usr/bin/env ruby
#

require 'time'
require 'json'
require 'fileutils'
require 'find'
require 'csv'

me=File.symlink?($0) ? File.readlink($0) : $0
ME=File.basename($0, ".rb")
MD=File.dirname(me)
LIB=File.realpath(File.join(MD, "..", "lib"))

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

require_relative "#{LIB}/logger"
require_relative "#{LIB}/o_parser"
require_relative "#{MD}/fwlog"
require_relative "#{MD}/format_xlsx"

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

FORMATS=[ "json", "xlsx", "csv" ]

$opts={
	:file=>nil,
	:filter=>/Shorewall:/,
	:in=>"enp2s0",
	:output=>nil,
	:name=>File.join(TMP,ME+"_output"),
	:label=>nil,
	:force=>false,
	:resolv=>false,
	:lookup=>false,
	:logger=>$log
}

$opts = OParser.parse($opts, "") { |opts|
	opts.on('-f', '--file FILE', String, "Kernel log to parse") { |file|
		$opts[:file]=file
	}

	opts.on('-I', '--in NET_DEV', String, "Network device, default=#{$opts[:in]}") { |inp|
		$opts[:in]=inp
	}

	opts.on('-O', '--output FORMAT', String, "Output format: [csv|xlsx]") { |type|
		type.downcase!
		format = FORMATS.include?(type) ? type.to_sym : nil
		raise "Unknown output format: #{type}" if format.nil?
		$opts[:output]=format
	}

	opts.on('-n', '--name FILE', String, "Output filename") { |name|
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
}
$opts[:in]=/IN=#{$opts[:in]}\s/

FWLog.init($opts)

ts_min=nil
ts_max=nil
entries={}
File.open($opts[:file], "r") { |fd|
	fd.each { |line|
		e = FWLog.parse(line, $opts)
		next if e.nil?
		entries[e.src] ||= []
		entries[e.src] << e
		ts = e.ts
		ts_min = ts if ts_min.nil? || ts_min > ts
		ts_max = ts if ts_max.nil? || ts_max < ts
	}
}

output_name = FWLog.output_name($opts[:name], ts_min, ts_max)

case $opts[:output]
when :xlsx
	FormatXLSX.init($opts)
	begin
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
	output_name+=".csv" if output_name[/\.csv$/].nil?
	$log.die "File exists: #{output_name}" if File.exists?(output_name) && !$opts[:force]
	$log.info "Writing #{output_name}"
	CSV.open(output_name, 'w') { |csv|
		csv << FWLog.to_a_headers
		entries.each_pair { |src,fwla|
			fwla.each { |fwl|
				# set :n to 0 to print every :src row
				csv << fwl.to_a(:n=>0)
			}
		}
	}
when :json
	puts JSON.pretty_generate(entries)
else
	puts "No output format specified"
end

