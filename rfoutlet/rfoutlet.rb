#!/usr/bin/env ruby
#

require 'json'
require 'fileutils'
require 'daemons'
require 'sun_times'

me=$0
if File.symlink?(me)
	me=File.readlink($0)
	md=File.dirname($0)
	me=File.realpath(me)
end
ME=File.basename(me, ".rb")
MD=File.dirname(me)
LIB=File.realpath(File.join(MD, "..", "lib"))

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")
HELP=File.join(MD, ME+".help")

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")
require_relative File.join(MD, "rf_outlet")
require_relative File.join(MD, "rfoutletconfig")

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)
YM=Time.now.strftime('%Y%m')
LOG_PATH=File.join(TMP, "#{ME}_#{YM}"+".log")

$opts={
	:outlet=>"o1",
	:state=>RFOutlet::OFF,
	:delay=>0,
	:sched=>{},
	:sunrise=>nil,
	:sunset=>nil,
	:lat=>nil,
	:long=>nil,
	:log => nil,
	:list => false,
	:daemonize => false,
	:logger => $log,
	:banner => "#{ME}.rb [options] process1 ...",
	:json=>ENV["RF_OUTLET_JSON"]||File.join(MD, "rfoutlet.json")
}

def random_delay_range(delay)
	delay=[0,1] if delay.nil?
	delay.each_index { |i|
		delay[i]=delay[i].to_i
		$log.die "Specified delay is not an integer: #{delay[i]}" unless delay[i].is_a?(Integer)
	}
	sdelay=delay[0]
	edelay=delay[1]
	if edelay.nil?
		# --sunrise 1800 will be a random delay from -900 to 900 seconds around the time of sunrise
		sdelay = sdelay / 2
		edelay = sdelay
		sdelay = -sdelay
	end
	delay=Random.rand(sdelay...edelay)
	$log.debug "Random integer between #{sdelay} and #{edelay}: #{delay}"
	delay
end

$opts = OParser.parse($opts, HELP) { |opts|
	# journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"
	opts.on('-o', '--outlet NUM', String, "Outlet number") { |num|
		$opts[:outlet]="o"+num
	}

	opts.on('-0', '--off', "Outlet off") {
		$opts[:state]=RFOutlet::OFF
	}

	opts.on('-1', '--on', "Outlet on") {
		$opts[:state]=RFOutlet::ON
	}

	opts.on('--sunrise [RANDOM]', Array, "Random seconds around time of sunrise") { |delay|
		$opts[:sunrise]=random_delay_range(delay)
	}

	opts.on('--sunset [RANDOM]', Array, "Random seconds around time of sunset") { |delay|
		$opts[:sunset]=random_delay_range(delay)
	}

	opts.on('--latlong LAT,LONG', Array, "Latitude and Longitude") { |array|
		$opts[:lat] = array[0].to_f
		$opts[:long] = array[1].to_f
	}

	opts.on('-d', '--delay TIMEOUT', Integer, "Random delay in seconds") { |delay|
		$opts[:delay] = Random.rand(0...delay)
	}

	opts.on('-j', '--json FILE', String, "JSON data file, default #{$opts[:json]}") { |json|
		if File.exists?(json)
			$log.debug "JSON data file=#{json}"
			$opts[:json]=json
		end
	}

	opts.on('-l', '--list', "List outlets") {
		$opts[:list]=true
	}

	opts.on('-L', '--log FILE', String, "Log file name, default to logging to console") { |log|
		$opts[:log]=log
	}

	opts.on('-b', '--bg', "Daemonize the script") {
		$opts[:daemonize]=true
	}
}

$log.debug $opts.inspect

RFOutletConfig.init($opts)
rfoc = RFOutletConfig.new($opts[:json])

if $opts[:list]
	rfoc.list
	exit 0
end

rfoc.set_outlet($opts[:outlet])

$opts[:lat] = rfoc.lat if $opts[:lat].nil?
$opts[:long] = rfoc.long if $opts[:long].nil?

if !$opts[:sunrise].nil? || !$opts[:sunset].nil?
	#today = Date.today
	now   = Time.now
	st = SunTimes.new

	sunrise = st.rise(now, $opts[:lat], $opts[:long])
	sunset  = st.set(now, $opts[:lat], $opts[:long])

	$log.debug "Sunrise/Sunset = #{sunrise.localtime}/#{sunset.localtime}"

	if sunrise < now
		sunrise = sunrise+86400
		$log.debug "Advancing sunrise to tomorrow: #{sunrise.localtime}"
	end

	if sunset < now
		sunset = sunset+86400
		$log.debug "Advancing sunset to tomorrow: #{sunset.localtime}"
	end

	tnow=now.to_i
	secs2sunrise=(sunrise.to_i-tnow)
	secs2sunset =(sunset.to_i-tnow)

	$log.debug "Secs to sunrise=#{secs2sunrise}"
	$log.debug "Secs to sunset =#{secs2sunset}"

	unless $opts[:sunrise].nil?
		$log.debug "Random sunrise adjustment #{$opts[:sunrise]}"
		secs2sunrise+=$opts[:sunrise]
		secs2sunrise = 0 if secs2sunrise < 0

		$opts[:sunrise]=secs2sunrise
		$opts[:sched][secs2sunrise]=RFOutlet::ON

		#TODO set timeout to turn off - 2 hours in the morning
		$opts[:sched][secs2sunrise+7200]=RFOutlet::OFF
	end

	unless $opts[:sunset].nil?
		$log.debug "Random sunset adjustment #{$opts[:sunset]}"
		secs2sunset += $opts[:sunset]
		secs2sunset = 0 if secs2sunset < 0
		$opts[:sunset]=secs2sunset
		$opts[:sched][secs2sunset]=RFOutlet::ON

		#TODO set timeout to turn off - 6 hours in the evening
		$opts[:sched][secs2sunset+21600]=RFOutlet::OFF
	end

	#puts $opts[:sched].inspect
	#$log.die "testing"
end

if $opts[:daemonize]
	$opts[:log]=LOG_PATH if $opts[:log].nil?
	$log.debug "Daemonizing script"
	Daemons.daemonize
end

$log=Logger.set_logger($opts[:log], Logger::INFO) unless $opts[:log].nil?
$log.level = Logger::DEBUG if $opts[:debug]
$opts[:logger]=$log
RFOutletConfig.init($opts)

#o=$opts[:outlet]
s=$opts[:state]
outlet=rfoc.outlet
oname=outlet.name

if $opts[:sched].empty?
	delay = $opts[:delay]
	if delay > 0
		$log.info "Sleeping #{delay} seconds before firing: #{oname}"
		sleep delay
	end
	rfcode=outlet.get_rfcode(s)
	$log.info "Turn #{s} outlet \"#{oname}\" [#{rfcode}]"
	$log.info outlet.sendcode(rfcode)
else
	#22142
	#75533
	#sleep 22142 seconds (6 hours)
	#sleep 75533-22142 seconds (14.8 hours later)
	adjust = 0
	$log.debug $opts[:sched].inspect

	sched=$opts[:sched]
	skeys=sched.keys.sort
	skeys.each { |key|
		secs=key+tnow
		state=sched[key]
		$log.info "Turn #{oname} #{state} at #{Time.at(secs).to_s}: delay=#{key}"
	}

	skeys.each { |delay|
		s = $opts[:sched][delay]
		delay -= adjust
		$log.info "Sleeping #{delay} seconds before setting #{oname} #{s}"
		begin
			sleep delay
		rescue Interrupt => e
			$log.warn "Caught exception: #{e.inspect}"
			# ignore Interrupt
			next
		ensure
			adjust += delay
		end

		rfcode=outlet.get_rfcode(s)
		$log.info "Turn #{s} outlet \"#{oname}\" [#{rfcode}]"
		$log.info outlet.sendcode(rfcode)
	}
end

