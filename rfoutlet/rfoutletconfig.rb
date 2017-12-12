
class RFOutletConfig
	@@log = Logger.new(STDOUT)

	ITEMS=[
		:DUMP,
		:OUTLETS,
		:NAMES,
		:ON,
		:OFF,
		:CODES
	]

	def self.items
		items=""
		ITEMS.each { |item|
			items+="#{item.to_s}, "
		}
		items.strip.chomp(",")
	end

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	attr_reader :config_file, :config, :outlets, :outlet, :lat, :long, :reload
	def initialize(config_file)
		@config = read_config(config_file)
		@lat = @config[:lat]
		@long = @config[:long]
		SchedSun.latlong(@lat, @long)
		@reload = false

		@outlets={}
		@config[:outlets].each_pair { |label, value|
			@outlets[label]=create_rfoutlet(label, value)
		}
	end

	def reloadQueue(reload=true)
		@reload = reload
	end

	def fillSchedQueue(queue)
		@reload = false
		@outlets.each { |outlet, rfo|
			next if rfo.sched.nil?
			if !rfo.sched.sunrise.nil? && rfo.sched.sunrise.enabled
				rfo.sched.sunrise.next_entries(rfo).each { |entry|
					queue.push entry
				}
			end
			if !rfo.sched.sunset.nil? && rfo.sched.sunset.enabled
				time = rfo.sched.sunset.next_entries(rfo).each { |entry|
					queue.push entry
				}
			end
		}
		queue
	end

	def create_rfoutlet(outlet, data)
		rfo=RFOutlet.new(outlet, data)
		sched=rfo.sched
		unless sched.nil?
			@@log.info sched.sunrise.describe unless sched.sunrise.nil?
			@@log.info sched.sunset.describe unless sched.sunset.nil?
			@@log.info sched.next.inspect
		end
		rfo
	rescue => e
		@@log.error e.message
		e.backtrace.each { |line|
			@@log.error line
		}
		raise e
	end

	def load_config(file)
		File.read(file)
	rescue => e
		@@log.die "Failed to read config #{file}: #{e}"
	end

	def read_config(file)
		@config_file=file
		JSON.parse(load_config(file), :symbolize_names=>true)
	rescue => e
		@@log.die "failed to parse json config in #{file}: #{e}"
	end

	def json_config
		JSON.pretty_generate(@config)
	rescue => e
		@@log.die "Failed to serialize @config to json"
	end

	def save_config
		backup_file="/var/tmp/%s_%s.json" % [ File.basename(@config_file, '.json'), Time.now.strftime("%Y%m%d_%H%M%S") ]
		@@log.info "Backing up #{@config_file} to #{backup_file}"
		FileUtils.mv(@config_file, backup_file)
		@@log.info "Writing updated config to #{@config_file}"
		File.open(@config_file, "w+") { |file|
			json=json_config
			file.print(json)
		}
	rescue => e
		@@log.die "Failed to backup config file to #{backup_file}"
	end

	def list
		@@log.debug JSON.pretty_generate(@config)
		@outlets.each_pair { |label, outlet|
			puts outlet.to_s
		}
	end

	def set_outlet(label)
		@outlet = @outlets[label.to_sym]
		@@log.die "Outlet not configured: #{label}" if @outlet.nil?
		@outlet
	end

	def all
		labels=[]
		@config[:outlets].keys.each { |label|
			labels << label.to_s
		}
		labels
	end

	def match(regex)
		labels=[]
		@config[:outlets].each_pair { |label,config|
			label = label.to_s
			name  = config[:name]
			@@log.debug "Testing #{name} against #{regex.to_s}"
			next if regex.match(name).nil?
			labels << label
		}
		labels
	end

	def item_dump
		load_config(@config_file)
	end

	def item_outlets
		@outlets.keys.to_json
	end

	def outlet_config(outlet)
		@config[:outlets][outlet.to_sym]
	end

	# outlet should be a symbol
	def update_outlet_config(outlet, data)
		#@config[:outlets].delete(outlet)
		@config[:outlets][outlet]=data
		@outlets[outlet]=create_rfoutlet(outlet, data)
		@@log.info JSON.pretty_generate(@config)
	end

	def outlet_config_json(outlet)
		oc=outlet_config(outlet)
		return nil if oc.nil?
		oc.to_json
	end

	def item_config(key)
		names={}
		@config[:outlets].each_pair { |outlet,config|
			names[outlet]=config[key]
		}
		names.to_json
	end

	def item_codes
		codes={}
		@config[:outlets].each_pair { |outlet,config|
			codes[outlet]={
				"on"=>config[:on],
				"off"=>config[:off]
			}
		}
		codes.to_json
	end

	# get a hash of all outlet items
	# hash_config[:name] -> { "o1"=>"Hallway", "o2"=>"Basement", ... }
	# @param key - symbol for key to hash
	# @return hash with outlet pointing to key
	#
	def hash_config(key)
		hash={}
		@config[:outlets].each_pair { |outlet,config|
			hash[outlet]=config[key]
		}
		hash
	end

	def print_item(item)
		case item.to_sym
		when :DUMP
			item_dump
		when :OUTLETS
			item_outlets
		when :NAMES
			item_config(:name)
		when :ON
			item_config(:on)
		when :OFF
			item_config(:off)
		when :CODES
			item_codes
		else
			@@log.die "Unknown item #{item}"
		end
	end
end
