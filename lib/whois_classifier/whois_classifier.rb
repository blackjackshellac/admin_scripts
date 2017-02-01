#!/usr/bin/env ruby
#
# whois classifier
#
# https://github.com/jekyll/classifier-reborn
#
#
#require 'classifier-reborn'
#lsi = ClassifierReborn::LSI.new
#strings = [ ["This text deals with dogs. Dogs.", :dog],
#            ["This text involves dogs too. Dogs! ", :dog],
#            ["This text revolves around cats. Cats.", :cat],
#            ["This text also involves cats. Cats!", :cat],
#            ["This text involves birds. Birds.",:bird ]]
#strings.each {|x| lsi.add_item x.first, x.last}
#
#lsi.search("dog", 3)
## returns => ["This text deals with dogs. Dogs.", "This text involves dogs too. Dogs! ",
##             "This text also involves cats. Cats!"]
#
#lsi.find_related(strings[2], 2)
## returns => ["This text revolves around cats. Cats.", "This text also involves cats. Cats!"]
#
#lsi.classify "This text is also about dogs!"
## returns => :dog
#

require 'classifier-reborn'

# A Latent Semantic Indexer by David Fayram. Latent Semantic Indexing
# engines are not as fast or as small as Bayesian classifiers, but are
# more flexible, providing fast search and clustering detection as well
# as semantic analysis of the text that theoretically simulates human learning.

lsi = ClassifierReborn::LSI.new

#% Information related to '213.202.232.0 - 213.202.235.255'
#% Abuse contact for '213.202.232.0 - 213.202.235.255' is 'abuse@myloc.de'
#inetnum:        213.202.232.0 - 213.202.235.255

data=[
	[ %q/Information related to '213.202.232.0 - 213.202.235.255'/, :inetnum ],
	[ %q/Abuse contact for '213.202.232.0 - 213.202.235.255' is 'abuse@myloc.de'/, :inetnum ],
	[ %q/inetnum:        213.202.232.0 - 213.202.235.255/, :inetnum ],
	[ %q/route:          213.202.232.0\/22/, :inetnum ]
]

data.each { |arr|
	lsi.add_item arr.first, arr.last
}

puts lsi.search("inetnum").inspect

puts lsi.find_related(data[2], 2).inspect

tests=[
%q/related to '213.202.232.0 - 213.202.235.255'/,
%q/foo is 213.202.232.0\/24/,
%q/this is garbage/
]

tests.each { |test|
	puts ">> "+test
	begin
		val=lsi.classify test
		puts "Result is: #{val.class} #{val}"
	rescue Vector::ZeroVectorError => e
		puts "No result found"
	end
}

