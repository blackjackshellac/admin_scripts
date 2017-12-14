#!/usr/bin/env ruby

require 'sun_times'

class SchedSun

	@@lat = 45.4966780
	@@long = -73.5039060

	def initialize()
		@sunTimes = SunTimes.new
	end

	def self.latlong(lat, long)
		@@lat = lat
		@@long = long
	end

	def next
		now	= Time.now
		time = @sunTimes.rise(now, @@lat, @@long)
		puts time.localtime.to_s
		time = @sunTimes.set(now, @@lat, @@long)
		puts time.localtime.to_s
	end
end

ss = SchedSun.new
ss.next
