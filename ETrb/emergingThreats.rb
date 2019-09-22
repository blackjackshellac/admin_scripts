#!/usr/bin/env ruby
#

# https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt
#

EThreats='https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt'

puts %x/ipset flush blacklist/
if $?.exitstatus == 1
  puts %x/ipset create blacklist hash:net/
end

ENTRY_RE=/^(?<entry>[^#]+).*$/

emergingBlockIPs="/tmp/emerging-Block-IPs.txt"

# Time.now.to_i - File.stat("emerging-Block-IPs.txt").mtime.to_i
age_in_seconds=0
if File.exists?(emergingBlockIPs)
	age_in_seconds=Time.now.to_i - File.stat(emergingBlockIPs).mtime.to_i
end

if age_in_seconds == 0 || age_in_seconds > 3600
	puts %x/wget -O #{emergingBlockIPs} #{EThreats}/
	if $?.exitstatus != 0
		puts "Error: failed to fetch #{emergingBlockIPs}"
		exit 1
	end
else
	puts "File #{emergingBlockIPs} already exists but is only #{age_in_seconds} seconds old"
end

page_content=File.read(emergingBlockIPs)
lines=page_content.split(/\s*\n/)
out=""
blacklist=[]
lines.each { |line|
  m = line.match(ENTRY_RE)
  next if m.nil?
  entry=m[:entry].strip
  next if entry.empty?
  blacklist << entry
}

puts "sorting blacklist of %d items" % blacklist.length

# a.b.c.d/e
# (\d+)\.(\d+)\.(\d+)\.(\d+)(\/\d+)
RE=/(?<n0>\d+)\.(?<n1>\d+)\.(?<n2>\d+)\.(?<n3>\d+)(\/\d+)?/
blacklist.sort! { |x,y|
  m=x.match(RE)
  n=y.match(RE)
  c=0
  [ :n0, :n1, :n2, :n3 ].each { |i|
    c=(m[i].to_i <=> n[i].to_i)
    break unless c == 0
  }
  #puts "%s %s %d" % [ x, y, c ]
  c
}

blacklist.each { |entry|
  #puts "ipset add blacklist #{entry}"
  out += %x/ipset add blacklist #{entry}/
  if $?.exitstatus != 0
  end
}

out.strip!
puts out

