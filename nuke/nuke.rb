#!/usr/bin/env ruby

require 'optparse'
require 'logger'
require 'wemote'
# ruby-sun-times gem
require 'sun_times'
require 'daemons'
require 'fileutils'

ME=File.basename($0, ".rb")
MD=File.dirname(File.realpath($0))
WEMO_ADDRESS=ENV["WEMO_ADDRESS"]||"wemo"
NOW=Time.now.strftime("_%Y%m%d")
LOG_PATH=File.join("/var/tmp/#{ME}", ME+NOW+".log")

require_relative(File.join(MD, "wemo_discover"))

class Logger
	def die(msg)
		self.error(msg)
		exit 1
	end
end

def set_logger(stream, level=Logger::INFO)
	log = Logger.new(stream)
	log.level = level
	log.datetime_format = "%Y-%m-%d %H:%M:%S"
	log.formatter = proc do |severity, datetime, progname, msg|
		"#{severity} #{datetime}: #{msg}\n"
	end
	log
end

$log=set_logger(STDOUT)

# :state
# :on
# :off
# :toggle

def get_delay(delay)
	delay=delay.to_i
	sign=(delay<0) ? -1 : +1
	delay=delay.abs if sign == -1
	(sign*rand(1+delay))
rescue => e
	$log.die "Failed to convert delay to random delay #{delay}: #{e}"
end

$o={
	:host => WEMO_ADDRESS,
	:action => :state,
	:name => nil,
	:daemonize => false,
	:delay => 0,
	:lat => (ENV["WEMO_LAT"]||45.4966780).to_f,
	:long => (ENV["WEMO_LONG"]||-73.5039060).to_f,
	:sunrise => nil,
	:sunset => nil,
	:log => nil,
	:debug => false
}
optparser = OptionParser.new do |opts|
	opts.banner = "#{ME}.rb [options]"

	opts.on('-a', '--host NAME', String, "hostname of wemo switch, default=#{$o[:host]} ENV=WEMO_ADDRESS") { |host|
		$o[:host]=host
	}

	opts.on('-n', '--name NAME', String, "find nemo by name") { |name|
		$o[:name]=name
	}

	opts.on('-s', '--state', "Get switch state") {
		$o[:action]=:state
	}

	opts.on('-1', '--on', "Set switch on") {
		$o[:action]=:on
	}

	opts.on('-0', '--off', "Set switch off") {
		$o[:action]=:off
	}

	opts.on('-t', '--toggle', "Toggle switch state") {
		$o[:action]=:toggle
	}

	opts.on('-d', '--delay SECS', Integer, "Delay before running command") { |delay|
		$o[:delay]=delay
	}

	opts.on('-r', '--random SECS', Integer, "Random delay before running command") { |delay|
		$o[:delay]=rand(1+delay.to_i)
	}

	opts.on('-L', '--latlong LATLONG', Array, "Lattitude and Longitude, default=#{$o[:lat]},#{$o[:long]} (see also env var WEMO_LAT and WEMO_LONG)") { |latlong|
		$log.die "LATLONG is an array of two integers" unless latlong.length == 2
		$o[:lat]=latlong[0].to_f
		$o[:long]=latlong[1].to_f
	}

	opts.on('-S', '--sunset DELAY', Integer, "Run at sunset with random delay") { |delay|
		$o[:sunset]=get_delay(delay)
		$o[:daemonize]=true
	}

	opts.on('-R', '--sunrise DELAY', Integer, "Run at sunrise with random delay") { |delay|
		$o[:sunrise]=get_delay(delay)
		$o[:daemonize]=true
	}

	opts.on('-D', '--debug', "Debug") {
		$o[:debug]=true
		$log.level = Logger::DEBUG
	}

	opts.on('-q', '--quiet', "Quiet") {
		$log.level = Logger::ERROR
	}

	opts.on('-b', '--[no-]bg', "Explicitly turn daemonize on/off") { |bg|
		$o[:daemonize]=bg
	}

	opts.on('-h', '--help', "Help") {
		puts opts
		exit 0
	}
end
optparser.parse!

$log.debug "lat=#{$o[:lat]} long=#{$o[:long]}"

if $o[:daemonize]
	$o[:log]=LOG_PATH if $o[:log].nil?
	FileUtils.mkdir_p(File.dirname($o[:log]))
	sout=$stdout
	$log.debug "Daemonizing script, logging to #{$o[:log]}"
	Daemons.daemonize
	sout.puts "Kill me with pid #{$$}"
end

level=$o[:debug] ? Logger::DEBUG : ($o[:quiet] ? Logger::WARN : Logger::INFO)
$log=set_logger($o[:log], level) unless $o[:log].nil?
$o[:logger]=$log

$log.info "Kill me with pid #{$$}" if $o[:daemonize]

fires={}
if $o[:sunset] || $o[:sunset]
	now   = Time.now
	st = SunTimes.new
	tnow=now.to_i

	times={}
	if $o[:sunrise]
			sunrise = st.rise(now, $o[:lat], $o[:long])
		$log.debug "Sunrise = #{sunrise.localtime}"

		if sunrise < now
			sunrise = sunrise+86400
			$log.debug "Advancing sunrise to tomorrow: #{sunrise.localtime}"
		end

		# add delay offset to time of sunrise
		sunrise=sunrise.to_i+$o[:sunrise]
		secs2sunrise=(sunrise.to_i-tnow)
		$log.debug "Secs to sunrise = #{secs2sunrise}"

		times[sunrise]=:on
		sunrise += (3600*3)
		times[sunrise]=:off
	end

	if $o[:sunset]
		sunset  = st.set(now, $o[:lat], $o[:long])

		$log.debug "Sunset = #{sunset.localtime}"
		if sunset < now
			sunset = sunset+86400
			$log.debug "Advancing sunset to tomorrow: #{sunset.localtime}"
		end

		# add delay offset to time of sunset
		sunset =sunset.to_i+$o[:sunset]
		secs2sunset =(sunset.to_i-tnow)

		$log.debug "Secs to sunset = #{secs2sunset}"

		times[sunset]=:on
		sunset += (3600*3)
		times[sunset]=:off
	end

	$log.debug "times=#{times.keys.inspect} stimes=#{times.keys.sort.inspect}"
	times.keys.sort.each { |time|
		action=times[time]
		$log.debug "time=#{time.inspect} Running at [#{Time.at(time)}] action=#{action.inspect}"
		fires[time]=action
	}

	$log.debug "fires=#{fires.inspect}"
end

unless $o[:name].nil?
	WemoDiscover::debug(true) if $log.level == Logger::DEBUG
	timeout=2
	wemos=WemoDiscover::search(timeout)
	$log.warn "No wemos found" if wemos.empty?
	wemos.each_pair { |addr, val|
		$log.info "Found wemo #{val[:fname]} at #{addr}"
		name=val[:fname]
		if $o[:name].eql?(name)
			$o[:host]=addr
			break
		end
	}
end

$log.info "Connecting to #{$o[:host]}"
switch = Wemote::Switch.new($o[:host])
$log.die "failed to connect to switch #{$o[:host]}" if switch.nil?

def printState(switch)
	state=switch.on? ? "on" : "off"
	$log.info "%s is %s" % [ switch.name, state ]
rescue Errno::EHOSTUNREACH => e
	$log.error "Failed to contact #{switch.name}: #{e}"
rescue => e
	$log.error "Caught unhandled exception: #{e}"
end

def fire(switch, action, delay)
	if delay > 0
		$log.info "Waiting %d seconds" % delay
		sleep(delay)
	end

	name=switch.name
	case action
	when :state
	when :on
		$log.info "Turn on #{name}"
		switch.on!
	when :off
		$log.info "Turn off #{name}"
		switch.off!
	when :toggle
		$log.info "Toggle #{name}"
		switch.toggle!
	else
		$log.die "Unknown switch action: #{action}"
	end

rescue Interrupt => e
	$log.warn "Caught interrupt"
	action=:state
ensure
	printState(switch) if action.eql?(:toggle) || action.eql?(:state)
end

if fires.empty?
	fire(switch, $o[:action], $o[:delay])
else
	fires.each_pair { |time, action|
		delay=time-Time.now.to_i
		fire(switch, action, delay)
	}
end

