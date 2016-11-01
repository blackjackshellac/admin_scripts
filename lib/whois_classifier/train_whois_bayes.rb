#!/usr/bin/env ruby
#

require 'classifier-reborn'
require 'json'

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

wbc = ClassifierReborn::Bayes.new $cat.keys

puts wbc.categories

RE_COMMENT=/(.*)(%.*)$/
RE_CAT=/([-\w]*):(.*)/

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
addresses=%w/213.202.233.59 185.53.91.76 70.81.251.194/
addresses.each { |addr|
	puts ">>> whois #{addr}"
	data=%x/whois #{addr}/
	data.split(/\n/).each { |line|
		line = $1 unless line[RE_COMMENT].nil?
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
