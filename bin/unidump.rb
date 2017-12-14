#!/usr/bin/env ruby
#

require "unicode/categories"

x="аррӏе.com"
puts x.codepoints.inspect
x.each_char { |c|
	puts "%s: %s %s %s %s" % [ c, c.ord, Unicode::Categories.categories(c), c.upcase, c.ord.chr(Encoding::UTF_8) ]
}
