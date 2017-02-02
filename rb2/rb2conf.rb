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
end

class Rb2Globals
	RB2G_DEST = "/mnt/backup"
	RB2G_LOGDIR = "/var/tmp/rb2"
	RB2G_EMAIL  = ""
	RB2G_SMTP   = "localhost"
	attr_accessor :dest, :logdir, :email, :smtp, :version, :conf

	def self.from_hash(h)
		h={} if h.nil?

		rb2g        = Rb2Globals.new
		rb2g.dest   = h[:dest]   ||RB2G_DEST
		rb2g.logdir = h[:logdir] ||RB2G_LOGDIR
		rb2g.email  = h[:email]  ||RB2G_LOGDIR
		rb2g.smtp   = h[:smtp]   ||RB2G_SMTP
		rb2g.conf   = Rb2Conf.from_hash(h[:conf])
		rb2g.version = Rb2Version.from_hash(h[:version])
		rb2g
	end

	def to_hash
		{
			:dest => @dest,
			:logdir => @logdir,
			:email => @email,
			:smtp => @smtp,
			:version => @version.to_hash,
			:conf => @conf.to_hash
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end
end

class Rb2Client
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
		@global = @config[:globals]
		@clients = @config[:clients]
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
		puts compact ? self.to_json : JSON.pretty_generate(self)
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
			:global=>@global.to_hash,
			:clients => @clients.to_hash
		}
	end

	def to_json(*a)
		to_hash.to_json(*a)
	end

end

