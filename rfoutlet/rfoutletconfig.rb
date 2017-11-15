
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

	attr_reader :config_file, :config, :outlets, :outlet, :lat, :long
	def initialize(config_file)
		@config = read_config(config_file)
		@lat = @config[:lat]
		@long = @config[:long]
		@outlets={}
		@config[:outlets].each_pair { |label, value|
			@outlets[label]=RFOutlet.new(label, value)
		}
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


