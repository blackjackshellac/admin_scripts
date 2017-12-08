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
      @duration = h[:duration].to_i||7200 # 2 hours by default

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

class SchedEntry
   @@log = Logger.new(STDOUT)

   def self.init(opts)
      @@log = opts[:logger] if opts.key?(:logger)
   end

   attr_reader :time, :rfo, :state
   def initialize(time, rfo, state)
      raise "Invalid outlet state in SchedEntry" if state != RFOutlet::ON && state != RFOutlet::OFF
      @time = time
      @rfo = rfo
      @state = state
   end

   def fire
      now = Time.now.to_i
      delay = @time-now
      sleep delay if delay > 0
      @rfo.turn(@state)
   end

end

class SchedQueue
   @@log = Logger.new(STDOUT)

   def self.init(opts)
      @@log = opts[:logger] if opts.key?(:logger)
   end

   def initialize
      @queue = []
      @lock = Mutex.new
   end

   def pop
      @lock.synchronize {
         len = @queue.length
         return nil if len == 0
         return @queue[0] if len == 1
         @queue.sort_by { |q|
            q.time
         }[0]
      }
   end

   def push(entry)
      raise "Invalid entry in SchedQueue" if entry.class != SchedEntry
      @lock.synchronize {
         @@log.info "Adding entry at time #{entry.time}: "+Time.at(entry.time).to_s
         @queue << entry
      }
   end

   def clear
      @lock.synchronize {
         @queue = []
      }
   end
end

class Sched
   @@log = Logger.new(STDOUT)

   def self.init(opts)
      @@log = opts[:logger] if opts.key?(:logger)
   end

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

   def self.thread_loop(queue)
      puts queue.inspect
      raise "queue is not a SchedQueue" if queue.class != SchedQueue
      loop {
         entry = nil
         begin
            entry = queue.pop
            if entry.nil?
               snooze = 5
               puts "Nothing in queue, sleeping for #{snooze}"
               sleep snooze
            else
               # sleep until this time
               @@log.info entry.inspect
               @@log.info entry.fire
            end
         rescue Interrupt => e

         rescue => e

         end
      }
   end

   def self.create_thread(queue)
      Thread.new {
         Sched.thread_loop(queue)
      }
   end
end
