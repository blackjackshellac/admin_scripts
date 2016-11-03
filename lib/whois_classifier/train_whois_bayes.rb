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

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")

#$cat = %w/abuse-c abuse-mailbox address admin-c country created descr fax-no inetnum last-modified mnt-by mnt-ref netname nic-hdl org organisation org-name org-type origin phone remarks role route source status tech-c/

$cat = {
	:netrange => %w/netrange inetnum/,
	:cidr     => %w/cidr route/,
	:country  => %w/country/,
	:regdate  => %w/regdate created/,
	:updated  => %w/updated last-modified/,
	:ignore   => %w//
}
$ignore = %w/abuse-c abuse-mailbox address phone fax-no org organisation org-name org-type netname status origin remarks admin-c tech-c mnt-ref mnt-by/
$ignore.concat(%w/descr source role nic-hdl mnt-routes mnt-domains person at https via nethandle parent nettype originas customer ref custname city stateprov postalcode orgtechhandle orgtechname orgtechphone orgtechemail orgtechref orgabusehandle orgabusename orgabusephone orgabuseemail orgabuseref rtechhandle rtechname rtechphone rtechemail rtechref organization orgname orgid comment/)

$log=Logger::set_logger(STDERR)

$opts = {
		:addresses => [],
		:file => nil,
		:data => File.join(TMP, "trained_classifier.dat"),
		:logger => $log
}

$opts = OParser.parse($opts, "") { |opts|
	opts.on('-a', '--addr LIST', Array, "One or more addresses to use for training") { |list|
		list.each { |addr|
			$opts[:addresses] << addr.strip
		}
	}

	opts.on('-i', '--input FILE', String, "Input file containing addresses for training") { |file|
		$opts[:file] = file
	}

	opts.on('--data FILE', String, "Classifier data, default #{$opts[:data]}") { |file|
		$opts[:data]=file
	}
}

RE_WHOIS_COMMENT=/(.*)(%.*)$/
RE_CAT=/([-\w]*):(.*)/

RE_SPACES=/\s+/
RE_COMMENT=/#.*$/
RE_DELIMS=/[\s,;:]+/
RE_IPV4=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
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

if File.exists?($opts[:data])
	data=File.read($opts[:data])
	wbc = Marshal.load data
else
	wbc = ClassifierReborn::Bayes.new $cat.keys
end

puts wbc.categories

def is_ignore(ignore_cats, cat)
	return ignore_cats.include?(cat)
end

def get_category(cat_h, cat)
	cat_h.each_pair { |kat, cats|
		return kat if cats.include?(cat)
	}
	nil
end

unknown={}
addresses=$opts[:addresses]
addresses.each { |addr|
	puts ">>> whois #{addr}"
	data=%x/whois #{addr}/
	data.split(/\n/).each { |line|
		line = $1 unless line[RE_WHOIS_COMMENT].nil?
		line.strip!
		next if line.empty?
		next if line[RE_CAT].nil?
		cat=$1.strip.downcase
		val=$2.strip

		next if unknown.keys.include?(cat)

		if is_ignore($ignore, cat)
			#puts "Debug: classify ignore #{cat}: #{line}"
			wbc.train(:ignore, line)
			next
		end
		kat = get_category($cat, cat)
		unless kat.nil?
			puts "Info: classify #{cat} as #{kat}: #{line}"
			wbc.train(kat, line)
			next
		end
		unknown[cat] = line
		puts "Warning: #{cat} category not found in input: #{line}"
	}
}

data = Marshal.dump wbc
$log.info "Writing whois training data: #{$opts[:data]}"
File.open($opts[:data], "w") { |fd|
	fd.write(data)
}
tests=[
	"inetnum:        70.81.251.0 - 70.81.251.255",
	"inetnum:        213.202.232.0 - 213.202.235.255"
]
tests.each { |test|
	cat=wbc.classify test
	puts "Classified as #{cat}: #{test}"
}

File.read("whois_sample.txt").each_line { |line|
	cat = wbc.classify(line)
	if cat == :cidr || cat.eql?(:cidr.to_s)
		puts "Info: cidr = #{line}"
		break
	end
}

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
