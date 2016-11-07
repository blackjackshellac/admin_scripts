#!/usr/bin/env ruby
#

require 'fileutils'
require 'classifier-reborn'
require 'json'

me=File.symlink?($0) ? File.readlink($0) : $0
ME=File.basename($0, ".rb")
MD=File.dirname(me)
LIB=File.realpath("..")

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")
TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

RE_SPACES=/\s+/
RE_COMMENT=/#.*$/
RE_DELIMS=/[\s,;:]+/
RE_IPV4=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")
require_relative "whois_bayes.rb"
require_relative "whois_data.rb"

#$cat = %w/abuse-c abuse-mailbox address admin-c country created descr fax-no inetnum last-modified mnt-by mnt-ref netname nic-hdl org organisation org-name org-type origin phone remarks role route source status tech-c/

$log=Logger::set_logger(STDERR)

$opts = {
		:addresses => [],
		:file => nil,
		:data => File.join(TMP, "trained_classifier.dat"),
		:logger => $log,
		:log => nil
}

$opts = OParser.parse($opts, "") { |opts|
	opts.on('-a', '--addr LIST', Array, "One or more addresses to use for training") { |list|
		list.each { |addr|
			addr.strip!
			raise "The given address does not appear to be a valid IPV4 address: #{addr}" if addr[RE_IPV4].nil?
			$opts[:addresses] << addr.strip
		}
	}

	opts.on('-i', '--input FILE', String, "Input file containing addresses for training") { |file|
		$opts[:file] = file
	}

	opts.on('--data FILE', String, "Classifier data, default #{$opts[:data]}") { |file|
		$opts[:data]=file
	}

	opts.on('-l', '--log FILE', String, "Optional log file") { |file|
		$opts[:log]=file
	}
}

unless $opts[:log].nil?
	$log=Logger::set_logger($opts[:log])
	$log.level = Logger::DEBUG if $opts[:debug]
	$opts[:logger]=$log
end

unless $opts[:file].nil?
	lines = File.read($opts[:file]).split(/\n/)
	lines.each { |line|
		line.gsub!(RE_SPACES, " ")
		line.gsub!(RE_COMMENT, "")
		line.strip!
		addrs = line.split(RE_DELIMS)
		$log.debug "addrs=#{addrs.inspect}"
		addrs.each { |addr|
			next if addr.empty?
			if addr[RE_IPV4].nil?
				$log.error "Invalid ip address: #{addr}"
				next
			end
			$log.debug "Adding #{addr}"
			$opts[:addresses] << addr
		}
	}
end

WhoisBayes.init($opts)
WhoisData.init($opts)

if File.exists?($opts[:data])
	wb = WhoisBayes.loadTraining($opts[:data])
else
	wb = WhoisBayes.new
end
$log.debug "Categories: #{wb.wbc.categories}"

addresses=$opts[:addresses]
addresses.each { |addr|
	wb.categorize(addr)
}

wb.saveTraining($opts[:data])

addresses.each { |addr|
	wb.classify_addr(addr)
}

tests=[
	"inetnum:        70.81.251.0 - 70.81.251.255",
	"inetnum:        213.202.232.0 - 213.202.235.255"
]
tests.each { |test|
	cat=wb.classify test
	puts "Classified as #{cat}: #{test}"
}

wd = wb.classify_file("whois_sample.txt")
puts JSON.pretty_generate(wd)

unknown = WhoisBayes.unknown
unless unknown.empty?
	puts JSON.pretty_generate(unknown)
	arr='%w/'
	unknown.keys.each { |key|
		arr+=key+" "
	}
	arr=arr.strip+'/'
	puts arr
end


#wbc.train_interesting "here are some good words. I hope you love them"
#wbc.train_uninteresting "here are some bad words, I hate you"
#puts wbc.classify "I hate bad words and you are good" # returns 'Uninteresting'

#classifier_snapshot = Marshal.dump wbc

# This is a string of bytes, you can persist it anywhere you like
#
# File.open("classifier.dat", "w") {|f| f.write(classifier_snapshot) }
# # Or Redis.current.save "classifier", classifier_snapshot
#
# # This is now saved to a file, and you can safely restart the application
# data = File.read("classifier.dat")
# # Or data = Redis.current.get "classifier"
# trained_classifier = Marshal.load data
# trained_classifier.classify "I love" # returns 'Interesting'
