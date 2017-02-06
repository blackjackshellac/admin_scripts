#
#
#

require 'json'
require 'fileutils'

# globals:
#  version:
#    major: '0'
#    minor: '9'
#    revision:
#  opts: "--acls --xattrs"
#  includes: ''
#  excludes: ''
#  dest: "/mnt/backup"
#  ninc: '5'
#  logdir: ''
#  logname: ''
#  email: [ abc@woot ]
#  smtp: localhost
#clients:
#  linguini:
#    address: localhost
#    includes: "/data,/home/steeve,/home/lissa,/home/etienne,/root,/etc,/usr/local"
#    excludes: "*/.gvfs/,*/.cache/"
#    opts: ''
#    ninc: '5'
#    compress: false
#    incrementals:

sample={
	:globals=> {
		:dest => "/mnt/backup",
		:logdir => "/var/tmp/rb2",
		:email => "",
		:smtp  => "localhost",
		:version => {
			:major => 0,
			:minor => 0,
			:revision => 0
		},
		:conf => {
			:opts=> "",
			:includes => [],
			:excludes => [],
			:nincrementals => 5,
			:compress => false
		}
	},
	:clients => {
		:linguini => {
			:address => "localhost",
			:conf => {
				:opts=> "",
				:includes => [],
				:excludes => [],
				:nincrementals => 5,
				:compress => false

			}
		}
	}
}

class Rb2Error < StandardError
end

class Rb2Version
	RB2V_MAJOR=0
	RB2V_MINOR=0
	RB2V_REVISION=0

	attr_accessor :major, :minor, :revision

	def self.from_hash(h)
		h={} if h.nil?
		rb2v = Rb2Version.new
		rb2v.major = h[:major]||RB2V_MAJOR
		rb2v.minor = h[:minor]||RB2V_MINOR
		rb2v.revision = h[:revision]||RB2V_REVISION
		rb2v
	end

	def to_hash
		{
			:major=>major,
			:minor=>minor,
			:revision=>revision
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end
end

class Rb2Conf
	KEYS=[:opts, :includes, :excludes, :nincrementals, :compress]
	RB2CONF_NINCREMENTALS=5
	RB2CONF_COMPRESS=false

	attr_accessor :opts, :includes, :excludes, :nincrementals, :compress

	def initialize
		@opts=""
		@includes=[]
		@excludes=[]
		@nincrementals=RB2CONF_NINCREMENTALS
		@compress=RB2CONF_COMPRESS
	end

	def append_key_array(key, ilist)
		var=instance_variable_get("@#{key}")
		raise Rb2Error, "Rb2Conf array variable #{key} unknown" if var.nil?
		ilist.each { |item|
			item.strip!
			next if var.include?(item)
			var << item 
		}
		var.uniq!
	end

	def delete_key_array(key, ilist)
		var=instance_variable_get("@#{key}")
		raise Rb2Error "Rb2Conf array variable #{key} unknown" if var.nil?
		ilist.each { |item|
			item.strip!
			raise Rb2Error, "Array #{key} does not contain item #{item}" unless var.include?(item)
			var.delete(item)
		}
		var.uniq!
	end

	def set_incrementals(nincrementals)
		nincrementals = RB2CONF_NINCREMENTALS if nincrementals.nil? || nincrementals <= 0
		@nincrementals = nincrementals
	end

	def self.from_hash(h)
		h={} if h.nil?
		rb2conf = Rb2Conf.new
		rb2conf.opts = h[:opts]||""
		rb2conf.includes = h[:includes]||[]
		rb2conf.excludes = h[:excludes]||[]
		rb2conf.nincrementals = h[:nincrementals]||RB2CONF_NINCREMENTALS
		rb2conf.compress = h[:compress]||RB2CONF_COMPRESS
		rb2conf
	end

	def to_hash
		{
			:opts=>@opts,
			:includes => @includes,
			:excludes => @excludes,
			:nincrementals => @nincrementals,
			:compress => @compress
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end

	def list(compact, indent="\t")
		KEYS.each { |key|
			var=instance_variable_get("@#{key}")
			puts "#{indent}#{key}: #{var}"
		}
	end
end

class Rb2Globals
	KEYS=[:dest, :logdir, :logformat, :syslog, :email, :smtp, :version, :conf]

	@@rb2g={
		:dest => "/mnt/backup",
		:logdir => "/var/tmp/rb2",
		:logformat => "rb2_%Y-%m-%d.log",
		:email => [],
		:smtp => "localhost",
		:syslog => false
	}

	@@rb2g_email = ""
	@@rb2g_smtp = "localhost"
	attr_accessor :dest, :logdir, :logformat, :syslog, :email, :smtp, :version, :conf

	def self.init(opts)
		[:dest, :logdir, :logformat, :syslog, :email, :smtp].each { |key|
			next unless opts.key?(key)
			raise Rb2Error, "Option value is null for #{key.inspect}" if opts[key].nil?
			@@rb2g[key]=opts[key]
		}
	end

	def self.from_hash(h)
		h={} if h.nil?

		rb2g           = Rb2Globals.new
		rb2g.dest      = h[:dest]   ||@@rb2g[:dest]
		rb2g.logdir    = h[:logdir] ||@@rb2g[:logdir]
		rb2g.logformat = h[:logformat] || @@rb2g[:logformat]
		rb2g.syslog    = h[:syslog] ||@@rb2g[:syslog]
		rb2g.email     = h[:email]  ||@@rb2g[:email]
		rb2g.smtp      = h[:smtp]   ||@@rb2g[:smtp]
		rb2g.conf      = Rb2Conf.from_hash(h[:conf])
		rb2g.version   = Rb2Version.from_hash(h[:version])
		rb2g
	end

	def set_option(key, val)
		raise Rb2Error, "No value for variable #{key}" if val.nil?
		var=instance_variable_get("@#{key}")	
		raise Rb2Error, "Unknown instance variable: #{key}=#{val}" if var.nil?
		clazz=var.class
		raise Rb2Error, "Incompatible instance var=#{clazz} val=#{val.class}" if clazz != val.class
		case var
		when String,TrueClass,FalseClass
			var = val
		when Array
			var.concat(val)
			var.uniq!
		else
			raise Rb2Error, "Class not handled in Rb2Globals.set_option: #{clazz}"
		end
		var
	end

	def delete_option(key, val)
		raise Rb2Error, "No value for variable #{key}" if val.nil?

		var=instance_variable_get("@#{key}")	
		raise Rb2Error, "Unknown instance variable: #{key}=#{val}" if var.nil?

		default=@@rb2g[key]
		raise Rb2Error, "No default value found for key=#{key}" if default.nil?

		clazz=var.class
		raise Rb2Error, "Incompatible instance var=#{clazz} val=#{val.class}" if clazz != val.class
		case var
		when String,TrueClass,FalseClass
			var = default
		when Array
			val.each { |v|
				var.delete(v)
			}
			var = default if var.empty?
		else
			raise Rb2Error, "Class not handled in Rb2Globals.set_option: #{clazz}"
		end
		var
	end

	def to_hash
		{
			:dest => @dest,
			:logdir => @logdir,
			:logformat => @logformat,
			:email => @email,
			:smtp => @smtp,
			:version => @version.to_hash,
			:conf => @conf.to_hash
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end

	def list(compact, indent="\t")
		KEYS.each { |key|
			var=instance_variable_get("@#{key}")
			raise Rb2Error, "Variable not defined for key=#{key.inspect}: #{self.to_json}" if var.nil?
			if var.class.method_defined? :list
				puts "#{indent}#{key}: #{var.list(compact, "\t"+indent)}"
			else
				puts "#{indent}#{key}: #{var}"
			end
		}
	end
end

class Rb2Client
	KEYS=[:client, :address, :conf]

	attr_accessor :client, :address, :conf

	def self.from_hash(client, h=nil)
		h={} if h.nil?

		rb2client = Rb2Client.new
		rb2client.client = client.to_s
		rb2client.address = h[:address]||"localhost"
		rb2client.conf = Rb2Conf.from_hash(h[:conf])
		rb2client
	end

	def set_address(addr)
		@address=addr
	end

	def set_incrementals(n)
		@conf.set_incrementals(n)
	end

	def delete_address(addr)
		return false unless @address.eql?(addr)
		@address=@client
		return true
	end

	def append_conf_key_array(key, ilist)
		@conf.append_key_array(key, ilist)
	end

	def delete_conf_key_array(key, ilist)
		@conf.delete_key_array(key, ilist)
	end

	def to_hash
		{
			:client  => @client,
			:address => @address,
			:conf => @conf.to_hash
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end

	def list(compact, indent="\t")
		KEYS.each { |key|
			var=instance_variable_get("@#{key}")
			if var.class.method_defined? :list
				puts "#{indent}#{key}: #{var.list(compact, "\t"+indent)}"
			else
				puts "#{indent}#{key}: #{var}"
			end
		}
	end
end

class Rb2Config
	CONF_ROOT="/etc/rb2/rb2.json"
	CONF_USER="#{ENV['HOME']}/.config/rb2/rb2.json"

	# class variables
	@@log = Logger.new(STDERR)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.get_conf(conf)
		if conf.nil?
			conf = (Process.uid == 0 ? CONF_ROOT : CONF_USER)
		else
			# ensure that user supplied configuration path is expanded
			conf = File.expand_path(conf)
		end
		@@log.debug "conf=#{conf}"
		conf
	end

	attr_reader :config_file, :config, :globals, :clients
	def initialize(conf=nil)
		conf=Rb2Config::get_conf(conf)
		@config_file = conf
		@config = read_config(conf)
		@globals = @config[:globals]
		@clients = @config[:clients]
		@@log.debug "globals=#{@globals.inspect}"
		@@log.debug "clients=#{@clients.inspect}"
	end

	def set_client_address(clist, alist)
		clist.each_index { |i|
			client=clist[i]
			address=alist[i]
			address=client if address.empty?

			@@log.debug "Set address=#{address} for #{client}"
			client=client.to_sym
			@clients[client]||=Rb2Client.from_hash(client)
			@@log.info "Set client #{client} address #{address}"
			@clients[client].set_address(address)
		}
	end

	def delete_client_address(clist, alist)
		clist.each_index { |i|
			client=clist[i]
			address=alist[i]
			client = client.to_sym
			@@log.die "Client config not found #{client}" if @clients[client].nil?
			@@log.warn "Client address not changed for #{client}: #{address}" unless @clients[client].delete_address(address)
		}
	end

	def set_client_conf_array(clist, ilist, key)
		clist.each { |client|
			client = client.to_sym
			@clients[client]||=Rb2Client.from_hash(client)
			begin
				@clients[client].append_conf_key_array(key, ilist)
			rescue Rb2Error => e
				@@log.error "#{client}: "+e.to_s
			end
		}
	end

	def set_client_includes(clist, ilist)
		set_client_conf_array(clist, ilist, :includes)
	end

	def set_client_excludes(clist, ilist)
		set_client_conf_array(clist, ilist, :excludes)
	end

	def set_client_incrementals(clist, nincrementals)
		clist.each { |client|
			client = client.to_sym
			@@log.die "Client config not found #{client}" if @clients[client].nil?
			@@log.debug "Set client #{client} nincrementals=#{nincrementals}"
			@clients[client].set_incrementals(nincrementals)
		}
	end

	# return val == nil if it failed
	def set_global_option(opts, key)
		val=opts[key]
		val=@globals.set_option(key, val)
		@@log.info "Set global option #{key}=#{val.inspect}"
	rescue => e
		@@log.error "Failed to set global option #{key}=#{val}: #{e.message}"
		val=nil
	ensure
		return val
	end

	def delete_global_option(opts, key)
		val=opts[key]
		var=@globals.delete_option(key, val)
		@@log.info "Deleted global option #{key}=#{val.inspect}"
	rescue Rb2Error => e
		@@log.error "Failed to delete global option #{key}=#{val}: #{e.message}"
		var=nil
	rescue => e
		@@log.error "Unexpected exception: #{e.to_s}"
		var=nil
	ensure
		return var
	end

	def delete_client_conf_array(clist, ilist, key)
		@@log.debug "clients=#{clist.inspect}"
		@@log.debug "  array=#{ilist.inspect}"
		@@log.debug "    key=#{key.inspect}"
		clist.each { |client|
			client = client.to_sym
			unless @clients.key?(client)
				@@log.warn "No client found: #{client}"
				next
			end
			begin
				@clients[client].delete_conf_key_array(key, ilist)
			rescue Rb2Error => e
				@@log.error "#{client}: "+e.to_s
			end
		}
	end

	def delete_client_includes(clist, ilist)
		delete_client_conf_array(clist, ilist, :includes)
	end

	def delete_client_excludes(clist, ilist)
		delete_client_conf_array(clist, ilist, :excludes)
	end

	def delete_clients(clist)
		@@log.debug "Deleting clients: #{clist.inspect}"
		clist.each { |client|
			client = client.to_sym
			@@log.debug "Deleting client #{client}: #{@clients[client].inspect}"
			@@log.warn "Client not found #{client}" if @clients.delete(client).nil?
		}
	end

	def list(compact)
		# TODO make compact a little more readable
		if compact
			@globals.list(compact,"")
			@clients.each_pair { |client,conf|
				puts conf.class
				puts "#{client}: #{conf.list(compact, "\t")}"
			}
		else
			puts JSON.pretty_generate(self)
		end
	end

	def load_config(conf)
		json=File.read(conf)
	rescue => e
		json="{}"
	ensure
		json
	end

	def parse_config(json)
		config=JSON.parse(json, :symbolize_names=>true)
	rescue => e
		# TODO empty config, probably shouldn't do this if the config is corrupted
		config={}
	ensure
		config
	end

	def read_config(conf)
		json=load_config(conf)
		@@log.debug "json=#{json}"
		config=parse_config(json)
		config[:globals]=Rb2Globals.from_hash(config[:globals])
		clients = config[:clients]||{}
		cc = {}
		clients.each_pair { |client,conf|
			@@log.debug "client=#{client} conf=#{conf.inspect}"
			cc[client.to_sym]=Rb2Client.from_hash(client, conf)
		}
		config[:clients]=cc
		config
	end

	def create_config_dir
		FileUtils.mkdir_p(File.dirname(@config_file))
	rescue Errno::EACCES => e
		@@log.die "Access error: #{e.to_s}"
	rescue => e
		e.backtrace.each { |b|
			puts b
		}
		raise "create_config_dir: Unexpected exception: #{e.to_s}"
	end

	def save_config_json(pretty = true)
		json = pretty ? JSON.pretty_generate(self) : self.to_json
		File.open(@config_file, "wt") { |fd|
			@@log.debug "Write json config to #{@config_file}"
			fd.puts(json)
		}
	rescue => e
		e.backtrace.each { |b|
			puts b
		}
		raise "save_config_json: Unexpected exception: #{e.to_s}"
	end

	def save_config(conf=nil)
		@config_file = conf unless conf.nil?
		create_config_dir
		save_config_json
	end

	def to_hash
		{
			:globals=>@globals.to_hash,
			:clients => @clients.to_hash
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end

end
