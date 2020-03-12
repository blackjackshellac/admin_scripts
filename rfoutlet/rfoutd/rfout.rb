#!/usr/bin/env ruby

require 'json'
require 'beaneater'
require 'optparse'

# if this is a symlink get the actual directory path of the script
me=File.symlink?($0) ? File.join(__dir__, File.basename($0)) : $0

ME=File.basename(me, ".rb")
MD=File.dirname(me)
RFLIB=File.realpath(File.join(MD, ".."))
LIB=File.realpath(File.join(MD, "../../lib"))

require_relative File.join(LIB, "logger")

$log=Logger.set_logger(STDOUT, Logger::INFO)

$opts = {
	:name => nil,
	:state => "on"
}
optparser = OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]"

	opts.on('-n', '--name NAME', String, "Name of outlet to match") { |name|
		$opts[:name] = name
	}
	
	opts.on('-a', '--all', "Use all known switches") {
		$opts[:name] = "all"
	}
	
	opts.on('-1', '--on', "Turn off") {
		$opts[:state]="on"
	}
	
	opts.on('-0', '--off', "Turn on") {
		$opts[:state]="off"
	}
		
	opts.on('-D', '--debug', "Turn on debugging output") {
		$log.level = Logger::DEBUG
	}

	opts.on('-h', '--help', "Help") {
		puts opts
		exit 0
	}
}
optparser.parse!

$log.error "Must specify at least one switch" if $opts[:name].nil?

$beanstalk = Beaneater.new('localhost:11300')

$tube = $beanstalk.tubes["rfoutlet"]
cmd={
	:name => $opts[:name],
	:state => $opts[:state]
}

$log.info "Sending #{JSON.pretty_generate(cmd)}"
$tube.put cmd.to_json
