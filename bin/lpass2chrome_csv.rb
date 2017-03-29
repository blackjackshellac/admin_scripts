#!/usr/bin/env ruby
#

require 'csv'
require 'open3'

#url,username,password,extra,name,grouping,fav

lpassfile=ARGV[0]
if lpassfile.nil? || lpassfile.empty?
	$stderr.puts "usage is: #{$0} <lpassfile.csv.gpg>"
	exit 1
end

lpdata=%x/gpg -d #{lpassfile}/
unless $?.exitstatus == 0
	$stderr.puts "Error opening file #{lpassfile}"
	exit 1
end

CSV::Converters[:blank_to_nil] = lambda { |field|
	field=nil if field && field.empty?
	field
}

# name,url,username,password
chrome_keys=[ :name, :url, :username, :password ]
chrome_data=[]

#[:url, :username, :password, :extra, :name, :grouping, :fav]
#
csv=CSV.parse(lpdata, :headers=>true, :header_converters => :symbol, :converters => [:all, :blank_to_nil])
# [:url, :username, :password, :extra, :name, :grouping, :fav]
$stderr.puts csv.headers.inspect
csv.each { |row|
	#puts row[:url].inspect
	entry={}
	chrome_keys.each { |key|
		raise "Key #{key} not found in #{row.inspect}" unless row.key?(key)
		entry[key]=row[key]
	}
	chrome_data << entry
}

$chrome_csv = CSV.generate(:headers => true, :header_converters => :symbol) { |csv|
	csv << chrome_keys
	chrome_data.each { |entry|
		a=[]
		chrome_keys.each { |key|
			a << entry[key]
		}
		csv << a
	}
}

runtime=Time.now
filename=runtime.strftime("chrome-%Y%m%d_%H%M%S.csv.gpg")
File.umask(0066)

#%x/echo "#{$chrome_csv}" | gpg -e -o "#{filename}"/
cmd=%Q/gpg -e -o "#{filename}" -/
$stderr.puts "cmd=#{cmd}"
Open3.popen3(cmd) {|stdin, stdout, stderr, wait_thr|
	pid = wait_thr.pid # pid of the started process.

	$chrome_csv.split(/\n/).each { |line|
		#$stderr.puts line
		#$stderr.flush
		stdin.puts(line)
	}
	stdin.close_write

	out=stdout.read
	puts "+++++\n"+stdout.read+"\n+++++" unless out.empty?

	exit_status = wait_thr.value # Process::Status object returned.
	if exit_status.exitstatus == 0
	else
		puts "====error===="
		puts stderr.read
		puts exit_status.inspect
		puts "====error===="
	end
}


# https://www.axllent.org/docs/view/export-chrome-passwords/
# Export Chrome / Chromium passwords to CSV
# 28 Oct 2016 in Security & Encryption
# As of July/August 2016 Google introduced a hidden feature
# that allows you to import & export your passwords. All you
# currently need to do is turn on the hidden feature in the
# chrome://flags settings and restart your browser, after
# which you'll have the required functionality.
#
# Instructions
#
# In your Google Chrome (or Chromium, whichever you use), type
# the following in your URL bar:
#
#      chrome://flags/#password-import-export, and then enable the feature.
#
# Restart your browser.
# Go to your passwords chrome://settings/passwords (you may have to
# wait a little while for your passwords to sync), then scroll down
# to below your passwords and you'll see two new buttons, Import & Export.
#
# Click Export, making sure you select the correct format (CSV).
# Thanks to Nishant Arora's post for the tip.
#
