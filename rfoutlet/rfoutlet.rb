#!/usr/bin/env ruby
#

require 'json'
require 'fileutils'
require 'daemons'
# gem install ruby-sun-times
require 'sun_times'

# if this is a symlink get the actual directory path of the script
me=File.symlink?($0) ? File.join(__dir__, File.basename($0)) : $0

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
require_relative File.join(MD, "sched")

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)
YM=Time.now.strftime('%Y%m')
LOG_PATH=File.join(TMP, "#{ME}_#{YM}"+".log")

$opts={
	:all=>false,
	:outlet=> nil,
	:names=>[],
	:outlets=>[],
	:state=>RFOutlet::ON,
	:delay=>0,
	:sched=>{},
	:sunrise=>nil,
	:sunset=>nil,
	:lat=>nil,
	:long=>nil,
	:log => nil,
	:json_item=>nil,
	:list => false,
	:sniff => false,
	:daemonize => false,
	:logger => $log,
	:banner => "#{ME}.rb [options] process1 ...",
	:json=>ENV["RF_OUTLET_JSON"]||File.join(MD, "rfoutlet.json")
}

# delay: two element array as input
#
# sdelay: delay[0] is start delay in seconds
# edelay: delay[1] is end delay in seconds
#
# If edelay is unset (nil) sdelay is split in half around zero
#
# sdelay=100 and edelay is nil
# sdelay becomes -50 and edelay becomes 50
#
def random_delay_range(delay)
	return 0 if delay.nil?
	raise "delay should be nil or Array" unless delay.class == Array

	[ 0, 1 ].each { |i|
		next if delay[i].nil?
		delay[i]=delay[i].to_i
	}

	sdelay=delay[0]
	$log.die "delay array cannot be null" if sdelay.nil?
	$log.die "Start delay is not an integer: #{sdelay.class}" unless sdelay.is_a?(Integer)

	# edelay is nil, split delay around 0 seconds
	edelay=delay[1]
	if edelay.nil?
		# --sunrise 1800 will be a random delay from -900 to 900 seconds around the time of sunrise
		sdelay = sdelay / 2
		edelay = sdelay
		sdelay = -sdelay
	else
		$log.die "End delay is not an integer: #{edelay}" unless edelay.is_a?(Integer)
	end
	delay=Random.rand(sdelay...edelay)
	$log.debug "Random integer between #{sdelay} and #{edelay}: #{delay}"
	delay
end

$opts = OParser.parse($opts, HELP) { |opts|
	# journalctl -k --since "2016-10-16 11:00:00" --until "2016-10-17 11:00:00"
	opts.on('-o', '--outlet NUM', String, "Outlet number") { |num|
		$opts[:outlet]="o"+num
		$opts[:outlets] << $opts[:outlet]
	}

	opts.on('-n', '--name NAME', String, "Outlet name (regex match)") { |name|
		$opts[:names] << name
		$opts[:names].uniq!
	}

	opts.on('-a', '--all', "All outlets") {
		$opts[:all]=true
	}

	opts.on('-0', '--off', "Outlet off") {
		$opts[:state]=RFOutlet::OFF
	}

	opts.on('-1', '--on', "Outlet on") {
		$opts[:state]=RFOutlet::ON
	}

	# turn on at sunrise, turn off at sunrise + random duration
	opts.on('--sunrise [RANDOM]', Array, "Random seconds around time of sunrise") { |delay|
		$opts[:sunrise]=random_delay_range(delay)
		$opts[:sunrise_off]=delay[2] unless delay[2].nil?
		puts "sunrise delay="+delay.inspect
	}

	opts.on('--sunset [RANDOM]', Array, "Random seconds around time of sunset") { |delay|
		$opts[:sunset]=random_delay_range(delay)
		$opts[:sunset_off]=delay[2] unless delay[2].nil?
	}

	opts.on('--latlong LAT,LONG', Array, "Latitude and Longitude") { |array|
		$opts[:lat] = array[0].to_f
		$opts[:long] = array[1].to_f
	}

	# Array - time,random seconds
	opts.on('--duration [RANDOM]', Array, "Random duration to toggle after sunrise, sunset") { |duration|
		$opts[:duration] = random_delay_range(duration)
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

	opts.on('-J', '--json-list ITEM', String, "Print json config to stdout: #{RFOutletConfig.items}") { |item|
		$opts[:json_item] = item
	}

	opts.on('-l', '--list', "List outlets") {
		$opts[:list]=true
	}

	opts.on('-s', '--sniff', "Sniff RF codes") {
		$opts[:sniff]=true
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

unless $opts[:json_item].nil?
	puts rfoc.print_item($opts[:json_item])
	exit 0
end
if $opts[:list]
	rfoc.list
	exit 0
end

if $opts[:sniff]
	exit RFOutlet.sniffer
end

$opts[:lat] = rfoc.lat if $opts[:lat].nil?
$opts[:long] = rfoc.long if $opts[:long].nil?

SchedSun.init($opts)

if !$opts[:sunrise].nil? || !$opts[:sunset].nil?
	#today = Date.today
	now   = Time.now
	st = SunTimes.new

	sunrise = st.rise(now, $opts[:lat], $opts[:long])
	sunset  = st.set(now, $opts[:lat], $opts[:long])

	$log.debug "Sunrise = #{sunrise.localtime}"
	$log.debug " Sunset = #{sunset.localtime}"

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
		secs2sunrise-=$opts[:sunrise]
		secs2sunrise = 0 if secs2sunrise < 0

		#$opts[:sunrise]=secs2sunrise
		$opts[:sched][secs2sunrise]=RFOutlet::ON

		duration=$opts[:duration]||7200
		if $opts.key?(:sunrise_off)
			$log.debug "Parsing sunrise off time: #{$opts[:sunrise_off]}"
			toff = Time.parse($opts[:sunrise_off])
			toff += 86400 if toff < sunrise
			duration = (toff.to_i-sunrise.to_i) # - $opts[:sunrise]
			toff = Time.at(sunrise+duration)
			$log.debug "Sunrise off at #{toff}: #{duration} seconds - delay #{$opts[:sunrise]} secs"
		end

		#TODO set timeout to turn off - 2 hours in the morning
		$opts[:sched][secs2sunrise+duration]=RFOutlet::OFF
	end

	unless $opts[:sunset].nil?
		$log.debug "Random sunset adjustment #{$opts[:sunset]}"
		secs2sunset -= $opts[:sunset]
		secs2sunset = 0 if secs2sunset < 0

		#$opts[:sunset]=secs2sunset
		$opts[:sched][secs2sunset]=RFOutlet::ON

		duration = $opts[:duration]||21600
		if $opts.key?(:sunset_off)
			$log.debug "Parsing sunset off time: #{$opts[:sunset_off]}"
			toff = Time.parse($opts[:sunset_off])
			toff += 86400 if toff < sunset
			duration = (toff.to_i-sunset.to_i)
			toff = Time.at(sunset+duration)
			$log.debug "Sunset off at #{toff}: #{duration} seconds - delay #{$opts[:sunset]} secs"
		end

		#TODO set timeout to turn off - 6 hours in the evening
		$opts[:sched][secs2sunset+duration]=RFOutlet::OFF
	end

	#puts $opts[:sched].inspect
	#$log.die "testing"
end

if $opts[:daemonize]
	$opts[:log]=LOG_PATH if $opts[:log].nil?
	$log.debug "Daemonizing script"
	Daemons.daemonize
end

# create a file logger if it has been specified
$log=Logger.set_logger($opts[:log], Logger::INFO) unless $opts[:log].nil?

# reset log level if debugging
$log.level = Logger::DEBUG if $opts[:debug]
$opts[:logger]=$log
# update the logger
RFOutletConfig.init({:logger=>$log})

$opts[:outlets] = rfoc.all if $opts[:all]

unless $opts[:names].empty?
	$opts[:names].each { |name|
		outlets=rfoc.match_name(name)
		next if outlets.empty?
		$log.debug "Found outlets for regex /#{name}/i : #{outlets.inspect}"
		$opts[:outlets].concat(outlets)
	}
end

$opts[:outlets].uniq!

$opts[:outlets].each { |label|
	rfoc.set_outlet(label)

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
}
