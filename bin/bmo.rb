#!/usr/bin/env ruby
#
# cleanup output from banking transaction
#

require 'logger'
require 'optparse'

ME=File.basename($0, ".rb")

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

FROM_TO_RE=/^(From|To)$/i
ACCOUNTS_RE=/^(Chequing|Savings|Other\s+\d+\s+\w+)\s+(.*)/i
KEY_COLON_DATA_RE=/^(?<key>.*?):(?<data>.*)$/
KNOWN_KEYS_RE=/^(From|To|Amount|Date|Reference#)$/i

def filter_data(key, hdata)
	# shouldn't happen
	raise "data hash has no output for key=#{key}" unless hdata.key?(key)

	out=hdata[key]

	return out if key[FROM_TO_RE].nil?

	# key is from or to
	if out[ACCOUNTS_RE].nil?
		out.gsub!(/\d/, "*")
	else
		acct=$1
		numb=$2.gsub(/\d/, "*")
		$log.debug "Account=#{acct} number=#{$2} numb=#{numb}"
		out="%s %s" % [ acct, numb ]
	end

	out
end

def process_transaction
	begin
		$log.info "Enter transaction data, type . to filter, Ctrl-C to quit"
		%x/stty -echo/
		lastkey=nil
		hdata={} 	# keyed data
		keys=[] 	# key order
		ARGF.each { |line|
			break unless line[/^\s*\.\s*/].nil?
			next if line.strip.empty?
			m=line.match(KEY_COLON_DATA_RE)
			unless m.nil?
				# matched input of format "key: data"
				key=m[:key]
				$log.warn "Unknown data key>> [#{key}]" if key[KNOWN_KEYS_RE].nil?
				data=m[:data]
				if keys.include?(key)
					$log.warn "Key already recorded #{key}, two transactions?"
				else
					keys << key unless keys.include?(key)
				end
				lastkey=key
			else
				key=lastkey
				if key.nil?
					$log.error "Unexpected input, no key for input data=[#{line}] ... ignoring"
					# key=nil, ignore input
					line=""
				else
					$log.warn "data not found for lastkey=#{key}" unless hdata.key?(key)
					d=hdata[key]||""
					line.prepend(d)
				end
				data=line
			end
			next if key.nil?
			hdata[key]=data.gsub(/\s+/, " ").strip
			puts "#{key}: #{hdata[key]}" unless hdata[key].empty?
		}

	rescue => e
	ensure
		%x/stty echo/
	end

	return if keys.empty?

	puts "\n+++++"
	keys.each { |key|
		out=filter_data(key, hdata)
		puts "#{key}: #{out}"
	}
	puts "+++++\n"
end

running=true
while running
	begin
		process_transaction
	rescue Interrupt => e
		$log.info "Caught interrupt, exiting"
		running=false
	rescue => e
		e.backtrace.each { |line|
			puts line
		}
		$log.die e.to_s
	end
end

exit 0

