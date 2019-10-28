#!/usr/bin/env ruby
#

require 'optparse'
require 'logger'
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

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

$opts={
	:mondirs=>[],
	:dryrun=>false,
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

	opts.on('-u', '--update', "Update the data") {
		$opts[:update]=true
	}
}

KEYS=%w/ftype mtime size uid gid/
def stat_path(path)
	lstat=File.lstat(path)
	pstat={}
	KEYS.each { |key|
		pstat[key]=lstat.send(key)
		next if pstat[key].class == String || pstat[key].class == Integer
		pstat[key] = pstat[key].to_s
	}
	pstat
end

def comp_stat(path, dstat, opts)
	pstat=stat_path(path)
	KEYS.each { |key|
		v=pstat[key]
		u = dstat[key]
		if u.nil?
			$log.warn "Path data missing for #{key}: #{path}"
		elsif !u.eql?(v)
			$log.warn "#{key} changed [#{v}] -> [#{u}] for #{dstat["ftype"]}: #{path}" unless v.eql?(u)
		else
			next
		end
		dstat[key]=v if opts[:update]
		opts[:changed]=true
	}
end

def find_data(dir, data, opts)
	update=opts[:update] ? true : data.empty?
	Find.find(dir) { |path|
		bn=File.basename(path)
		if data.key?(path)
			comp_stat(path, data[path], opts)
		else
			stat=stat_path(path)
			if update
				$log.warn "Updating #{path}"
			else
				$log.warn "Update to add #{stat["ftype"]} #{path}"
			end
			data[path]=stat if opts[:update]
			opts[:changed]=true
		end
	}

	data.keys.each { |path|
		next if File.exist?(path)
		if opts[:update]
			$log.info "Adding missing path #{path}"
			data.delete(path)
		else
			$log.error "#{data[path]["ftype"].capitalize} deleted "+path unless opts[:update]
		end
		opts[:changed]=true
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
	return unless opts[:update]
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
	unless $opts[:update]
		$log.warn "Run #{ME} --update"
		exit 1
	end
end

