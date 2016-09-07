#!/usr/bin/env ruby
#

require 'optparse'
require 'logger'
require 'json'
require 'fileutils'
require 'find'

ME=File.basename($0, ".rb")
md=File.dirname($0)
FileUtils.chdir(md) {
	md=Dir.pwd().strip
}
MD=md
HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")

LIB=File.realpath(File.join(MD, "..", "lib"))
require_relative "#{LIB}/logger"
require_relative "#{LIB}/o_parser"

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

$opts={
	:mondirs=>[],
	:dryrun=>false,
	:populate=>false,
	:update=>false,
	:changed=>false,
	:logger=>$log
}

$opts = OParser.parse($opts, "") { |opts|
	opts.on('-d', '--dir NAME', String, "Directory to monitor") { |dir|
		$opts[:mondirs] << File.realpath(dir)
	}

	opts.on('-n', '--dry-run', "Dry run") {
		$opts[:dryrun]=true
	}

	opts.on('-p', '--populate', "Repopulate data for given dirs") {
		$opts[:populate]=true
	}

	opts.on('-u', '--update', "Update the data") {
		$opts[:update]=true
	}
}

KEYS=[:ftype, :mtime, :size, :uid, :gid]
def stat_path(path)
	lstat=File.lstat(path)
	pstat={}
	KEYS.each { |key|
		pstat[key]=lstat.send(key.to_s)
		next if pstat[key].class == String || pstat[key].class == Fixnum
		pstat[key] = pstat[key].to_s
	}
	#pstat[:ftype]=lstat.ftype
	#pstat[:mtime]=lstat.mtime
	#pstat[:size]=lstat.size
	#pstat[:uid]=lstat.uid
	#pstat[:gid]=lstat.gid
	pstat
end

def comp_stat(path, dstat, opts)
	pstat=stat_path(path)
	KEYS.each { |key|
		v=pstat[key]
		key=key.to_s
		unless dstat.key?(key)
			opts[:changed]=true
			$log.warn "Path data missing for #{key}: #{path}"
			if opts[:update]
				dstat[key]=v
			end
			continue
		end
		u = dstat[key]
		unless v.eql?(u)
			opts[:changed]=true
			$log.warn "#{key} changed [#{u}] != [#{v}] for: #{path}"
			if opts[:update]
				dstat[key]=v
			end
		end
	}
end

def find_data(dir, data, opts)
	populate=opts[:populate] ? true : data.empty?
	Find.find(dir) { |path|
		if data.key?(path)
			comp_stat(path, data[path], opts)
		else
			if populate
				$log.debug "Populating #{path}"
			else
				$log.warn "Populating: #{path}"
			end
			data[path]=stat_path(path)
		end
	}

	data.keys.each { |path|
		next if File.exist?(path)
		$log.error "File missing: "+path
		opts[:changed]=true
		data.delete(path) if opts[:update]
	}

	$log.debug "ohash=#{$opts.object_id}"

	data
#rescue => e
#	$log.die "Failed to find data in #{dir}: #{e}"
end

def read_monitor_data(jsonf)
	data={}
	json=File.exists?(jsonf) ? File.read(jsonf) : "{}"
	JSON.parse(json)
rescue => e
	$log.die "failed to read data file: #{jsonf}: #{e}"
end

def write_monitor_data(jsonf, data, opts)
	$log.info "Writing data to #{jsonf}"
	return if opts[:dryrun]
	File.open(jsonf, "w+") { |fd|
		fd.puts JSON.pretty_generate(data)
	}
rescue => e
	$log.error "Failed to write monitor data: #{jsonf}"
	$log.debug "data="+data.inspect
	$log.die "exiting"
end

def monitor(dir, opts={ :dryrun=>false })
	jsonf=File.join(TMP, dir.gsub(/\//, "_")+".json")
	$log.info "Monitoring #{dir}: #{jsonf}"
	data=read_monitor_data(jsonf)
	data=find_data(dir, data, opts)
	write_monitor_data(jsonf, data, opts)
end

$log.debug "ohash=#{$opts.object_id}"

dirs=$opts[:mondirs]
$log.die "No dirs specified for monitoring" if dirs.empty?
dirs.each { |dir|
	monitor(dir, $opts)
}

$log.debug "options="+$opts.inspect
if $opts[:changed]
	$log.warn "Run #{ME} --update"
	exit 1
end

