#!/usr/bin/env ruby
#

require 'json'

$outlets=JSON.parse(File.read("rfoutlet.json"), :symbolize_names=>true)
puts JSON.pretty_generate($outlets)

CODESEND="/var/www/html/rfoutlet/codesend"
def outlet(outlet, state)
	puts "Set outlet \"#{$outlets[outlet.to_sym][:name]}\": #{state}"
	puts %x[#{CODESEND} #{$outlets[outlet.to_sym][state.to_sym]}]
end

o=ARGV[0]||:o1
s=ARGV[1]||:on

outlet(o, s)

