#!/usr/bin/env ruby

require 'optparse'
require 'logger'
require 'wemote'

ME=File.basename($0, ".rb")
MD=File.dirname(File.expand_path($0))
WEMO_ADDRESS=ENV["WEMO_ADDRESS"]||"wemo"

class Logger
	def die(msg)
		self.error(msg)
		exit 1
	end
end

def set_logger(stream)
	log = Logger.new(stream)
	log.level = Logger::INFO
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

$o={
	:host => WEMO_ADDRESS,
	:action => :state,
	:name => nil,
	:delay => 0
}
optparser = OptionParser.new do |opts|
	opts.banner = "#{ME}.rb [options]"

	opts.on('-a', '--host NAME', String, "hostname of wemo switch, default=#{$o[:host]}") { |host|
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

	opts.on('-D', '--debug', "Debug") {
		$log.level = Logger::DEBUG
	}

	opts.on('-q', '--quiet', "Quiet") {
		$log.level = Logger::ERROR
	}

	opts.on('-h', '--help', "Help") {
		puts opts
		exit 0
	}
end
optparser.parse!

if $o[:delay] > 0
	$log.info "Waiting %d seconds" % $o[:delay]
	sleep($o[:delay])
end

if $o[:name].nil?
	$log.info "Connecting to #{$o[:host]}"
	switch = Wemote::Switch.new($o[:host])
	$log.die "failed to connect to switch #{$o[:host]}" if switch.nil?
else
	switch = Wemote::Switch.find($o[:name])
	$log.die "failed to connect to switch #{$o[:name]}" if switch.nil?
end

def printState(switch)
	state=switch.on? ? "on" : "off"
	$log.info "%s is %s" % [ switch.name, state ]
end

name=switch.name
action=$o[:action]
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

printState(switch) if action.eql?(:toggle) || action.eql?(:state)

