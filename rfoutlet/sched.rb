# gem install ruby-sun-times
require 'sun_times'

class SchedSun

   @@lat = 45.4966780
   @@long = -73.5039060

   def self.latlong(lat, long)
      @@lat = lat
      @@long = long
   end

	attr_reader :enabled, :before, :after, :duration
	def initialize(type, h)
		@type = type
		@enabled = h[:enabled]||false
		@before = (h[:before]||0).to_i
		@after = (h[:after]||0).to_i
      @duration = (h[:duration]||7200).to_i # 2 hours by default

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

   def fire(delay=nil)
      now = Time.now.to_i
      delay = @time-now if delay.nil?
      if delay > 0
         @@log.info "Sleeping #{delay} seconds before firing"
         sleep delay
      end
      @@log.info "Run rfo.turn(#{@state}): #{@rfo.to_s}"
      @rfo.turn(@state)
   end

   def to_s
      "Entry %s/%s/%s" % [ Time.at(@time).strftime("%Y%m%d_%H%M%S"), @rfo.to_s, @state ]
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
         @@log.info "Found #{len} entries on queue"
         return nil if len == 0
         #return @queue.delete_at(0) if len == 1
         @queue.sort_by! { |q|
             q.time
         }.delete_at(0)
      }
   end

   def push(entry)
      raise "Invalid entry in SchedQueue" if entry.class != SchedEntry
      @lock.synchronize {
         @@log.info "Adding #{entry.state} entry at time #{Time.at(entry.time)}: #{entry.rfo.to_s}"
         @queue << entry
         @@log.info "Now #{@queue.length} entries in queue"
      }
      #puts dump
   end

   def clear
      @lock.synchronize {
         @queue = []
      }
   end

   def slump
      @lock.synchronize {
         s=@queue.sort_by { |e|
            e.time
         }
         puts "Dumping #{s.length} entries"
         s.each { |entry|
            puts "Dump: "+entry.to_s
         }
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
               snooze = 1
               #puts "Nothing in queue, sleeping for #{snooze}"
               sleep snooze
            else
               # sleep until this time
               @@log.info entry.to_s
               @@log.info entry.fire
			   queue.slump
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
