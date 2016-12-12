#!/usr/bin/env ruby
#
# cleanup output from banking transaction
#

require 'logger'
require 'optparse'

ME=File.basename($0, ".rb")
MD=File.expand_path(File.dirname(File.realpath($0)))

require_relative File.join(MD, "KeyDataTransaction")

class Logger
	def err(msg)
		self.error(msg)
	end

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

$log = set_logger(STDERR)

optparser=OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]\n"

	opts.on('-d', '--debug', "Enable debugging output") {
		$log.level = Logger::DEBUG
	}

	opts.on('-h', '--help', "Help") {
		$stdout.puts ""
		$stdout.puts opts
		exit 0
	}
}
optparser.parse!

KeyDataTransaction.init(:logger=>$log)

transactions=[]
while
	tra = KeyDataTransaction.process
	break if tra.nil?
	transactions << tra unless tra.empty?
end

puts "\nSummarizing ..."
transactions.each { |trans|
	trans.playback
}


exit 0

