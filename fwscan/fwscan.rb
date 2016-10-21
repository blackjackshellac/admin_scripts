#!/usr/bin/env ruby
#

require 'time'
require 'json'
require 'fileutils'
require 'find'

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

case $opts[:output]
when :xlsx
	FormatXLSX.init($opts)
	begin
		TIME_FMT="%Y%m%d-%H%S"
		sts_min = ts_min.strftime(TIME_FMT)
		sts_max = ts_max.strftime(TIME_FMT)
		name = "%s_%s_%s" % [ $opts[:name], sts_min, sts_max ]
		fxlsx = FormatXLSX.new(name, $opts[:label], $opts)
	rescue => e
		$log.die "Failed to create xlsx object: #{e}"
	end
	row=0
	row = fxlsx.write_headers(row, 0, %w/Src TimeStamp In Proto DstPort PortName SrcName/)
	entries.each_pair { |src,fwla|
		n=0
		fwla.each { |fwl|
			a=[]

			src = n==0 ? fwl.src : ""

			a << src
			a << fwl.ts
			a << fwl.in
			a << fwl.proto
			a << fwl.dpt
			a << FWLog.service(fwl.dpt)
			a << FWLog.hostname(fwl.src)
			row = fxlsx.write_row(row, 0, a)

			n+=1
		}
	}
	fxlsx.close
when :csv
when :json
	puts JSON.pretty_generate(entries)
else
	puts "No output format specified"
end

