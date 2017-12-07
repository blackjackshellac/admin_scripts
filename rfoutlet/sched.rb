# gem install ruby-sun-times
require 'sun_times'

class SchedSun

   @@lat = 45.4966780
   @@long = -73.5039060

   def self.latlong(lat, long)
      @@lat = lat
      @@long = long
   end

	attr_reader :enabled, :before, :after
	def initialize(type, h)
		@type = type
		@enabled = h[:enabled]||false
		@before = h[:before].to_i||0
		@after = h[:after].to_i||0

      raise "Unknown sched type in SchedSun: #{@type}" if @type != :sunrise && @type != :sunset
	end

	def describe
		"%s: from %d seconds before %s to %d seconds after" % [ @enabled, @before, @type, @after]
	end

   def get_tweak
      b=-@before
      a=@after

      if b < a
         range=b...a

         tweak = Random.rand(range)
      else
         tweak = 0
      end
      tweak
   end

	def next
      now   = Time.now
      st = SunTimes.new

		if @type == :sunrise
         time = st.rise(now, @@lat, @@long)
		elsif @type == :sunset
         time = st.set(now, @@lat, @@long)
		end

      time += get_tweak

      # if we're past the time already, advance to tomorrow
      time += 86400 if time < now
      time.to_i
	end
end

class Sched
	attr_reader :sunrise, :sunset
	def initialize(h)
		@sunrise = h[:sunrise].nil? ? nil : SchedSun.new(:sunrise, h[:sunrise])
		@sunset =  h[:sunset].nil? ? nil : SchedSun.new(:sunset, h[:sunset])
	end

	def next
		times=[]
		times << @sunrise.next unless @sunrise.nil?
		times << @sunset.next  unless @sunset.nil?
		times.sort!
	end
end
