# gem install ruby-sun-times
require 'sun_times'

class SchedSun

	@@lat = 45.4966780
	@@long = -73.5039060

	def self.latlong(lat, long)
		@@lat = lat
		@@long = long
	end

	DEFAULTS = {
		:enabled => false,
		:before => 0,
		:after => 0,
		:duration => 7200
	}
	attr_reader :enabled, :before, :after, :duration
	def initialize(type, h)
		@type = type
		raise "Unknown sched type in SchedSun: #{@type}" if @type != :sunrise && @type != :sunset

		set_fields(h)
	end

	def defval(h, key)
		h={} if h.nil?
		h[key]||DEFAULTS[key]
	end

	def set_fields(h)
		@enabled = defval(h, :enabled)
		@before = defval(h, :before).to_i
		@after = defval(h, :after).to_i
		@duration = defval(h, :duration).to_i
	end

	def describe
		"%s: from %d seconds before %s to %d seconds after" % [ @enabled, @before, @type, @after]
	end

	def next_entries(rfo)
		entries = []
		if @enabled
			time = next_time
			entries << SchedEntry.new(time[0], time[1], rfo, RFOutlet::ON)
			time = next_time(@duration)
			entries << SchedEntry.new(time[0], time[1], rfo, RFOutlet::OFF)
		end
		entries
	end

	#
	# return an array of two elements
	# times[0] = time of next sunrise/sunset
	# times[1] = random tweak from -@before to +@after times[0]
	#
	def next_time(duration=0)
		now	= Time.now
		st = SunTimes.new

		if @type == :sunrise
			time = st.rise(now, @@lat, @@long)
		elsif @type == :sunset
			time = st.set(now, @@lat, @@long)
		end

		rtweak = random_tweak
		time = is_tomorrow(now, time+duration+rtweak)

		[ time, rtweak ]
	end

	def random_tweak
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

	# if we're past the sunrise or sunset time already, advance to tomorrow's
	def is_tomorrow(now, time)
		time += 86400 if time < now
		time.to_i
	end

	private :next_time, :is_tomorrow, :random_tweak

end

class SchedEntry
	@@log = Logger.new(STDOUT)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	attr_reader :time, :random, :rfo, :state
	def initialize(time, random, rfo, state)
		raise "Invalid outlet state in SchedEntry" if state != RFOutlet::ON && state != RFOutlet::OFF
		@time = time
		@random = random # random tweak
		@rfo = rfo
		@state = state
	end

	def fire
		now = Time.now.to_i
		delay = @time+@random-now if delay.nil?
		if delay > 100
			#@@log.debug "Delay too long, iterating sleep: #{delay}"
			return false
		end
		# almost time to fire, wait for a bit
		if delay > 0
			@@log.info "Sleeping #{delay} seconds before firing"
			sleep delay
		end
		# enough waiting, let's do this
		@@log.info "Run rfo.turn(#{@state}): #{@rfo.to_s}"
		@rfo.turn(@state)
		true
	end

	def to_s
		"Entry %s (%s)/%s/%s" % [ Time.at(@time).strftime("%Y%m%d_%H%M%S"), @random.to_s, @rfo.to_s, @state ]
	end

	def eql?(other)
		return false if other.nil? || other.class != SchedEntry
		(other.time == @time && other.state.eql?(@state) && other.rfo.eql?(@rfo))
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

	##
	# Push SchedEntry onto SchedQueue
	def push(entry)
		raise "Invalid entry in SchedQueue" if entry.class != SchedEntry
		@lock.synchronize {
			if @queue.any? { |e|	entry.eql?(e) }
				@@log.info "Entry is already on queue: "+entry.to_s
			else
				@@log.info "Adding #{entry.state.upcase} entry at time #{Time.at(entry.time+entry.random)}: #{entry.rfo.to_s}"
				@queue << entry
				@@log.info "Now #{@queue.length} entries in queue"
			end
		}
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

	# {:outlet=>"o6",
	# 	:data=>{
	# 	:name=>"Stairway xmas lights",
	# 	:code=>"0304-2",
	# 	:on=>"5330371",
	# 	:off=>"5330380",
	# 	:sched=>{
	# 		:sunrise=>{:enabled=>true, :before=>"3600", :after=>"0", :duration=>"7200"},
	# 		:sunset=>{:enabled=>true, :before=>"1800", :after=>"300", :duration=>"21600"}
	# 	}
	# }
	# }
	def update_entry(outlet, data)
		@lock.synchronize {
			@queue.each { |entry|
				entry.rfo.update(outlet, data)
			}
		}
	end
end

class Sched
	@@log = Logger.new(STDOUT)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		SchedEntry.init(opts)
		SchedQueue.init(opts)
	end

	attr_reader :sunrise, :sunset
	def initialize(h)
		@sunrise = h[:sunrise].nil? ? nil : SchedSun.new(:sunrise, h[:sunrise])
		@sunset =  h[:sunset].nil? ? nil : SchedSun.new(:sunset, h[:sunset])
	end

	def update(data)
		if data.key?(:sunrise)
			if @sunrise.nil?
				@sunrise = SchedSun.new(:sunrise, data[:sunrise])
			else
				@sunrise.set_fields(data[:sunrise])
			end
		else
			@sunrise = nil
		end
		if data.key?(:sunset)
			if @sunset.nil?
				@sunset = SchedSun.new(:sunset, data[:sunset])
			else
				@sunset.set_fields(data[:sunset])
			end
		else
			@sunset = nil
		end
	end

	def self.thread_loop(queue, rfoc)
		raise "queue is not a SchedQueue" if queue.class != SchedQueue

		snooze = 1

		entry = nil
		loop {
			begin
				if rfoc.reload
					$log.info "Reloading queue"
					rfoc.fillSchedQueue(queue)
				end

				# reuse the same entry if it's not nil
				entry = queue.pop if entry.nil?
				unless entry.nil?
					# got an entry, try to fire
					entry = nil if entry.fire
				end
				# sleep for a bit before retrying
				sleep snooze
			rescue Interrupt => e
				@@log.warn "Caught interrupt, continuing"
			rescue => e
				@@log.warn "Caught exception: #{e.message}"
			end
		}
	end

	def self.create_thread(queue, rfoc)
		Thread.new {
			Sched.thread_loop(queue, rfoc)
		}
   end

	def next_entries(rfo)
		entries=[]
		if !@sunrise.nil?
			entries.concat(@sunrise.next_entries(rfo))
		end
		if !@sunset.nil?
			entries.concat(@sunset.next_entries(rfo))
		end
		entries
	end
end
