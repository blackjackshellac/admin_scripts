#!/usr/bin/env ruby

require 'json'
require 'time'

WTF_EMAIL=ENV['WTF_EMAIL']||""
WTF_HOST=ENV['WTF_HOST']||""

WTF_MYIP="/tmp/wtf_myip.json"
WTF_TIME=Time.now
WTF_NOW=WTF_TIME.to_s
WTF_TIMEOUT=600
WTF_DATA={
	:time=>WTF_NOW,
	:ip=>""
}

def parse_time(time)
	begin
		Time.parse(time)
	rescue TypeError => e
		raise Errno::ENOENT, "Invalid time value #{time}"
		WTF_TIME
	rescue ArgumentError => e
		raise Errno::ENOENT, "Invalid time string #{time}"
		WTF_TIME
	end
end

def read_myip
	myip=WTF_DATA
	begin
		puts "Reading #{WTF_MYIP}"
		json=File.read(WTF_MYIP)
		puts "Parsing json"
		myip=JSON.parse(json, :symbolize_names => true)
		raise Errno::ENOENT, "Time not found in data file #{WTF_MYIP}" unless myip.key?(:time)
		t0 = parse_time(myip[:time])
		t1 = WTF_TIME
		l=(t1-t0).to_i
		if l > 0 && l < WTF_TIMEOUT
			puts "Too soon to check: last checked #{l} seconds ago, check again in #{WTF_TIMEOUT-l} seconds"
			exit 0
		end
	rescue Errno::ENOENT => e
		myip=WTF_DATA
	rescue => e
		puts "#{e.class} #{e.message}"
		e.backtrace.each { |l|
			puts l
		}
		exit 1
	end
	myip
end

def check_myip(url, myip)
	cmd="curl --silent #{url}"
	puts cmd
	my_current_ip=%x/#{cmd}/.strip
	puts ".%s. .%s." % [ myip[:ip], my_current_ip ]
	if myip[:ip].eql?(my_current_ip)
		puts "My IP has not changed: #{my_current_ip}"
		return false
	end
	puts "My IP has changed: #{my_current_ip}"
	myip={
		:ip=>my_current_ip,
		:time=>WTF_NOW
	}
	write_myip(myip)
	notify_email(myip)
	return true
end

def write_myip(myip)
	puts "Writing to #{WTF_MYIP}"
	File.open(WTF_MYIP, "w") { |fd|
		#fd.puts JSON.pretty_generate(myip)
		fd.puts myip.to_json
	}
rescue => e
	puts "ERROR: #{e.class}: #{e.message}"
	exit 1
end

def notify_email(myip)
	return if WTF_EMAIL.nil? || WTF_EMAIL.empty?
	json=JSON.pretty_generate(myip)
	host=%x/hostname -s/.strip
	subj="#{host}: IP address has changed: #{myip[:ip]}"
	%x/echo "#{json}" | mail -s "#{subj}" #{WTF_EMAIL}/
rescue => e
	puts "Error #{$?.exitstatus}: failed to notify #{WTF_EMAIL} [#{e.class}: #{e.to_s}]"
end

myip = read_myip
puts "My ip is [#{myip[:ip]}], time is #{myip[:time]}"

#curl ipv4bot.whatismyipaddress.com
urls=[]
#urls << "ipv4bot.whatismyipaddress.com"
url="https://wtfismyip.com/text"

check_myip(url, myip)

