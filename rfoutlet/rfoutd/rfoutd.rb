#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'daemons'
# gem install ruby-sun-times
require 'sun_times'
# gem install beaneater
require 'beaneater'

# if this is a symlink get the actual directory path of the script
me=File.symlink?($0) ? File.join(__dir__, File.basename($0)) : $0

ME=File.basename(me, ".rb")
MD=File.dirname(me)
RFLIB=File.realpath(File.join(MD, ".."))
LIB=File.realpath(File.join(MD, "../../lib"))

require_relative File.join(LIB, "logger")
require_relative File.join(RFLIB, "rf_outlet")
require_relative File.join(RFLIB, "rfoutletconfig")
require_relative File.join(RFLIB, "sched")

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")
HELP=File.join(MD, ME+".help")

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)
YM=Time.now.strftime('%Y%m')
LOG_PATH=File.join(TMP, "#{ME}_#{YM}"+".log")

$opts = {
	:daemonize => true,
	:debug => true,
	:log => nil,
	:logger => $log,
	:host => "*",
	:port => 11321,
	:json=>ENV["RF_OUTLET_JSON"]||File.join(File.expand_path("~/bin"), "rfoutlet.json")
}
	
if $opts[:daemonize]
	$opts[:log]=LOG_PATH if $opts[:log].nil?
	$log.debug "Daemonizing script"
	#Daemons.daemonize
end

# create a file logger if it has been specified
$log=Logger.set_logger($opts[:log], Logger::INFO) unless $opts[:log].nil?

# reset log level if debugging
$log.level = Logger::DEBUG if $opts[:debug]
$opts[:logger]=$log
# update the logger
RFOutletConfig.init({:logger=>$log})
$rfoc = RFOutletConfig.new($opts[:json])

addr='127.0.0.1:11300'
$log.debug "Beanstalk listening on #{addr}"
@beanstalk = Beaneater.new(addr)
@rfotube=@beanstalk.tubes["rfoutlet"]

@beanstalk.tubes.each { |tube|
	$log.info "tube=#{tube}"
}

# cmd={ :name=> "xmas", :state=>"off" }
# @rfotube.put cmd.to_json
def process(cmds)
	cmds.each { |jcmd|
		$log.info "cmd=#{jcmd}"
		cmd=JSON.parse(jcmd)
		name=cmd["name"]
		outlets = name.eql?("all") ? $rfoc.all : $rfoc.match_name(name)
		if outlets.nil?
			$log.error "Name #{name} not found"
			continue
		end
		state=RFOutlet.get_state(cmd["state"])
		outlets.each { |label|
			$log.info "Outlet #{label.to_s}"
			$rfoc.set_outlet(label)

			outlet=$rfoc.outlet
			oname=outlet.name

			rfcode=outlet.get_rfcode(state)
			$log.info "Turn #{state} outlet \"#{oname}\" [#{rfcode}]"
			$log.info outlet.sendcode(rfcode)			
		}
			
	}
end

loop do
	timeout = 5
	jobs = []

	begin
		jobs << @rfotube.reserve(timeout)
	rescue Beaneater::TimedOutError
		# nothing to do
		# $log.debug "Nothing to do, sleeping"
		#sleep 5
		jobs = []
	rescue Interrupt
		break
	end

	next if jobs.empty?
	
	process(jobs.map { |job| job.body })

	jobs.map { |job|
		job.delete
	}
end

$log.info "Closing down"
@beanstalk.close
