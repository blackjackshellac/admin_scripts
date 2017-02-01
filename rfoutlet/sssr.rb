#!/usr/bin/env ruby
#
#
#timezone is borked in sunriseset datetime output
#require 'sunriseset'
require 'sun_times'

lat,long="45.4966780,-73.5039060".split(/,/)
lat=lat.to_f
long=long.to_f

today=Date.today
now  =Time.now
#now=DateTime.now
#now=DateTime.parse(DateTime.now.strftime("%Y-%m-%dT%H:%M:%S+00:00"))
puts " now="+now.to_s

#sunrise=srs.sunrise
#sunset =srs.sunset
st=SunTimes.new
sunrise=st.rise(now, lat, long)
sunset =st.set(now, lat, long)

puts "rise="+sunrise.to_s
puts " set="+sunset.to_s
puts

if sunrise < now
	puts "Advancing sunrise to tomorrow"
	sunrise = sunrise+86400
end

if sunset < now
	puts "Advancing sunset to tomorrow"
	sunset = sunset+86400
end

puts "Next sunrise/sunset"
puts "rise="+sunrise.to_s
puts " set="+sunset.to_s
puts

tnow=now.to_time.to_i

secs2sunrise=(sunrise.to_time.to_i-tnow)
secs2sunset =(sunset.to_time.to_i-tnow)
puts "Seconds until next sunrise/sunset"
puts "rise-now="+secs2sunrise.to_s
puts " set-now="+secs2sunset.to_s
puts

ss=Time.at(tnow+secs2sunset)
sr=Time.at(tnow+secs2sunrise)
puts "sr="+sr.to_s
puts "ss="+ss.to_s
puts
