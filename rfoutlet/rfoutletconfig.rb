
class RFOutletConfig
	@@log = Logger.new(STDOUT)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	attr_reader :config, :outlets, :outlet, :lat, :long
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
end


