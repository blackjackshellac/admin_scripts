#!/usr/bin/env ruby
#

require 'classifier-reborn'

#CAT = %w/abuse-c abuse-mailbox address admin-c country created descr fax-no inetnum last-modified mnt-by mnt-ref netname nic-hdl org organisation org-name org-type origin phone remarks role route source status tech-c/

CAT = {
	:netrange => %w/netrange inetnum/,
	:cidr     => %w/cidr route/,
	:country  => %w/country/,
	:regdate  => %w/regdate created/,
	:updated  => %w/updated last-modified/
}
IGNORE = {

}

wbc = ClassifierReborn::Bayes.new CAT.keys

puts wbc.categories

RE_COMMENT=/(.*)(%.*)$/
RE_CAT=/([-\w]*):(.*)/

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
		found=nil
		CAT.each_pair { |kat, cats|
			next unless cats.include?(cat)

			puts "Info: classify #{cat} as #{kat}: #{val}"
			wbc.train(kat, line)
			found=kat
			break
		}
		next unless found.nil?
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
