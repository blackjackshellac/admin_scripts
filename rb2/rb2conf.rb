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


class Rb2Error < StandardError
end

class Rb2Shutdown < StandardError
end

module Rb2Defs
	# http://www.railstips.org/blog/archives/2009/05/15/include-vs-extend-in-ruby/
	#
	# Even though include is for adding instance methods, a common idiom you’ll see in
	# Ruby is to use include to append both class and instance methods. The reason for
	# this is that include has a self.included hook you can use to modify the class that
	# is including a module and, to my knowledge, extend does not have a hook. It’s
	# highly debatable, but often used so I figured I would mention it. Let’s look at
	# an example.
	def self.included(base)
		base.extend(ClassMethods)
	end

	module ClassMethods
		@@rb2defs = {}

		def dump_defaults(prefix)
			puts "+++++"
			puts "#{prefix} rb2defs.object_id=#{@@rb2defs.object_id}"
			puts "#{prefix} rb2defs=#{@@rb2defs.inspect}"
			puts "+++++"
		end

		def set_default(key, val)
			raise Rb2Error, "Default value already set" if @@rb2defs.key?(key)
			#puts "Setting default #{key}=#{val}"
			@@rb2defs[key]=val
		end

		def get_default(key, dup=true)
			raise Rb2Error, "No default value for key #{key}" unless @@rb2defs.key?(key)
			#dump_defaults("get_default")
			if dup
				begin
					return @@rb2defs[key].clone
				rescue => e
					# ugly not clonable hack for Fixnum, Fixnum strangely can't be cloned even though it has method_defined?(:clone)
				end
			end
			@@rb2defs[key]
		end

		def is_default(opts, key)
			val=opts[key]
			var=get_default(key, false)
			#puts "is_default default=#{var} key=#{key} val=#{val}"
			#dump_defaults("is_default")

			clazz=var.class
			raise Rb2Error, "Incompatible default value var=#{clazz} val=#{val.class}" if clazz != val.class

			case val
			when NilClass, String, Array, TrueClass, FalseClass, Fixnum
				(val == var)
			else
				raise Rb2Error, "Class not handled in Rb2Globals.set_option: #{clazz}"
			end
		end
	end
end

#
# Rb2KeyVal
#
# include this module in class to share methods with class instance
# extend this module in class to share methods with class itself
#
module Rb2KeyVal
	def init_option(key, val)
		instance_variable_set("@#{key}", val)
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
		instance_variable_set("@#{key}", var)
		var
	end

	def get_option(key)
		raise Rb2Error, "Unknown global variable: #{key}" unless KEYS_GLOBALS.include?(key)
		var=instance_variable_get("@#{key}")
        raise Rb2Error, "Unknown instance variable: #{key}" if var.nil?
		var
	end

	def delete_option(key, val, default)
		raise Rb2Error, "No value for variable #{key}" if val.nil?

		var=instance_variable_get("@#{key}")
		raise Rb2Error, "Unknown instance variable: #{key}=#{val}" if var.nil?

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

	def list_key(compact, indent, key)
		var=instance_variable_get("@#{key}")
		clz=var.class
		if clz.method_defined? :list
			var.list(compact, "\t"+indent)
		elsif clz == Array
			puts "#{indent}#{key}: '#{var.join(",")}'"
		elsif clz == String
			puts "#{indent}#{key}: '#{var}'"
		else
			puts "#{indent}#{key}: #{var}"
		end
	end

	def list_keys(compact, indent, keys)
		keys.each { |key|
			list_key(compact, indent, key)
		}
	end
end

class Rb2Version
	include Rb2KeyVal

	KEYS_VERSION=[:major, :minor, :revision]

	RB2V_MAJOR=2
	RB2V_MINOR=0
	RB2V_REV=0

	attr_accessor :major, :minor, :revision

	def self.from_hash(h)
		h={} if h.nil?
		rb2v = Rb2Version.new
		rb2v.major = h[:major].to_i||RB2V_MAJOR
		rb2v.minor = h[:minor].to_i||RB2V_MINOR
		rb2v.revision = h[:revision]||RB2V_REV
		if RB2V_MAJOR != h[:major].to_i
			# TODO can detect config version changes here
			rb2v.major=RB2V_MAJOR
			rb2v.minor=RB2V_MINOR
			rb2v.revision=RB2V_REV
		end
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

	def list(compact, indent="\t")
		list_keys(compact, indent, KEYS_VERSION)
		#KEYS_VERSION.each { |key|
		#	var=instance_variable_get("@#{key}")
		#	if var.class.method_defined? :list
		#		var.list(compact, "\t"+indent)
		#	else
		#		puts "#{indent}#{key}: #{var}"
		#	end
		#}
	end

	def to_s
		"%s %s.%s.%s" % [ Rb2Config::CONF_NAME, @major, @minor, @revision ]
	end
end

class Rb2Conf
	include Rb2KeyVal
	include Rb2Defs

	KEYS_CONF=[:sshopts, :includes, :excludes, :nincrementals, :compress]
	RB2CONF_NINCREMENTALS=5
	RB2CONF_COMPRESS=false

	Rb2Conf.set_default(:sshopts, "")
	Rb2Conf.set_default(:includes, [])
	Rb2Conf.set_default(:excludes, [])
	Rb2Conf.set_default(:nincrementals, RB2CONF_NINCREMENTALS)
	Rb2Conf.set_default(:compress, RB2CONF_COMPRESS)

	attr_accessor :sshopts, :includes, :excludes, :nincrementals, :compress
	def initialize
		KEYS_CONF.each { |key|
			init_option(key, Rb2Conf::get_default(key))
		}
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
		rb2conf.sshopts = h[:sshopts]||"-a -v -v --relative --delete-excluded --ignore-errors --one-file-system --xattrs"
		rb2conf.includes = h[:includes]||[]
		rb2conf.excludes = h[:excludes]||[]
		rb2conf.nincrementals = h[:nincrementals]||RB2CONF_NINCREMENTALS
		rb2conf.compress = h[:compress]||RB2CONF_COMPRESS
		rb2conf
	end

	def to_hash
		{
			:sshopts=>@sshopts,
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
		list_keys(compact, indent, KEYS_CONF)
	end
end

class Rb2Globals
	include Rb2KeyVal
	include Rb2Defs

	KEYS_GLOBALS=[:dest, :logdir, :logformat, :syslog, :email, :smtp, :version, :conf]

	Rb2Globals::set_default(:dest, "/mnt/backup")
	Rb2Globals::set_default(:logdir, "/var/tmp/rb2")
	Rb2Globals::set_default(:logformat, "rb2_%Y%m%d_%H%M%S.log")
	Rb2Globals::set_default(:email, [])
	Rb2Globals::set_default(:smtp, "localhost")
	Rb2Globals::set_default(:syslog, false)

	attr_accessor :dest, :logdir, :logformat, :syslog, :email, :smtp, :version, :conf
	def initialize
		KEYS_GLOBALS.each { |key|
			case key
			when :conf, :version
				# do nothing
			else
				init_option(key, Rb2Globals::get_default(key))
			end
		}
	end

	def self.init(opts)
		# init @@log from opts[:logger] if necessary
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.from_hash(h)
		h={} if h.nil?

		rb2g           = Rb2Globals.new
		rb2g.dest      = h[:dest]   ||Rb2Globals::get_default(:dest)
		rb2g.logdir    = h[:logdir] ||Rb2Globals::get_default(:logdir)
		rb2g.logformat = h[:logformat] || Rb2Globals::get_default(:logformat)
		rb2g.syslog    = h[:syslog] ||Rb2Globals::get_default(:syslog)
		rb2g.email     = h[:email]  ||Rb2Globals::get_default(:email)
		rb2g.smtp      = h[:smtp]   ||Rb2Globals::get_default(:smtp)
		rb2g.conf      = Rb2Conf.from_hash(h[:conf])
		rb2g.version   = Rb2Version.from_hash(h[:version])
		rb2g
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
		list_keys(compact, indent, KEYS_GLOBALS)
			#var=instance_variable_get("@#{key}")
			#raise Rb2Error, "Variable not defined for key=#{key.inspect}: #{self.to_json}" if var.nil?
			#if var.class.method_defined? :list
			#	puts "#{indent}#{key}:"
			#	var.list(compact, "\t"+indent)
			#else
			#	puts "#{indent}#{key}: #{var}"
			#end
	end
end

class Rb2Client
	include Rb2KeyVal

	KEYS_CLIENT=[:client, :address, :conf]

	attr_accessor :client, :address, :conf

	def self.from_hash(client, h=nil)
		h={} if h.nil?

		rb2client = Rb2Client.new
		rb2client.client = client.to_s
		rb2client.address = h[:address]||client.to_s
		rb2client.conf = Rb2Conf.from_hash(h[:conf])
		rb2client
	end

	def get_ssh_address
		@address.eql?("localhost") ? nil : @address
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
		list_keys(compact, indent, KEYS_CLIENT)
		#KEYS_CLIENT.each { |key|
		#	var=instance_variable_get("@#{key}")
		#	if var.class.method_defined? :list
		#		puts "#{indent}#{key}:"
		#		var.list(compact, "\t"+indent)
		#	else
		#		puts "#{indent}#{key}: #{var}"
		#	end
		#}
	end
end

class Rb2Config
	CONF_NAME="rb2"
	CONF_ROOT="/etc/rb2/#{CONF_NAME}.json"
	CONF_USER="#{ENV['HOME']}/.config/rb2/#{CONF_NAME}.json"

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

	attr_reader :config_file, :config, :globals, :clients, :updated
	def initialize(conf=nil)
		conf=Rb2Config::get_conf(conf)
		@config_file = conf
		@config = read_config(conf)
		@globals = @config[:globals]
		@clients = @config[:clients]
		@@log.debug "globals=#{@globals.inspect}"
		@@log.debug "clients=#{@clients.inspect}"

		@updated = false
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
			@updated = true
		}
	end

	def delete_client_address(clist, alist)
		clist.each_index { |i|
			client=clist[i]
			address=alist[i]
			client = client.to_sym
			@@log.die "Client config not found #{client}" if @clients[client].nil?
			@@log.warn "Client address not changed for #{client}: #{address}" unless @clients[client].delete_address(address)
			@updated = true
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

	def set_client_config(opts, option)
		clist = opts[:clients]
		clist.each { |client|
			cc=get_client_conf(client, true)
			conf=cc.conf
			val=conf.set_option(option, opts[option])
			@@log.info "Set client #{client} option #{option}=#{val.inspect}"
			@updated = true
		}
	rescue => e
		@@log.error "Failed to set client config #{option}: clients=#{clist.inspect} [#{e.to_s}]"
		val=nil
	ensure
		return val
	end

	def set_global_config(opts, key)
		val=opts[key]
		val=@globals.conf.set_option(key, val)
		@@log.info "Set global config #{key}=#{val.inspect}"
		@updated = true
	rescue => e
		@@log.error "Failed to set global config #{key}=#{val}: #{e.message}"
		val=nil
	ensure
		return val
	end

	def delete_global_config(opts, key)
		val=opts[key]
		var=@globals.conf.delete_option(key, val, Rb2Conf::get_default(key))
		@@log.info "Deleted global config #{key}=#{var.inspect}"
		@updated = true
	rescue Rb2Error => e
		@@log.error "Failed to delte global config #{key}=#{val}: #{e.message}"
		var=nil
	rescue => e
		@@log.error "Unexpected exception: #{e.to_s}"
		var=nil
	ensure
		return var
	end

	# return val == nil if it failed
	def set_global_option(opts, key)
		val=opts[key]
		val=@globals.set_option(key, val)
		@@log.info "Set global option #{key}=#{val.inspect}"
		@updated = true
	rescue => e
		@@log.error "Failed to set global option #{key}=#{val}: #{e.message}"
		val=nil
	ensure
		return val
	end

	def get_global_option(key)
		@globals.get_option(key)
	rescue Rb2Error => e
		$log.die "Failed to get global option: #{key} [#{e.messsage}]"
	rescue => e
		$log.die "Failed to get global option: #{key} [#{e.to_s}]"
	end

	def delete_global_option(opts, key)
		val=opts[key]
		var=@globals.delete_option(key, val, Rb2Globals::get_default(key))
		@@log.info "Deleted global option #{key}=#{val.inspect}"
		@updated = true
	rescue Rb2Error => e
		@@log.error "Failed to delete global option #{key}=#{val}: #{e.message}"
		var=nil
	rescue => e
		@@log.error "Unexpected exception: #{e.to_s}"
		var=nil
	ensure
		return var
	end

	def get_client_conf(client, create=false)
		puts "client=#{client}"
		client=client.to_sym
		puts "clients="+@clients.inspect
		if @clients[client].nil?
			raise Rb2Error, "Client #{client} config not found" unless create
			@clients[client]=Rb2Client.from_hash(client)
		end
		@clients[client]
	rescue Rb2Error => e
		$log.die "Failed to get #{client} config: #{key} [#{e.messsage}]"
	rescue => e
		$log.die "Failed to get #{client} config: #{key} [#{e.to_s}]"
	end

	def print_version
		puts @globals.get_option(:version).to_s
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
				@updated = true
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
			if @clients.delete(client).nil?
				@@log.warn "Client not found #{client}"
				next
			end
			@updated = true
		}
	end

	def list(compact, indent="")
		# TODO make compact a little more readable
		if compact
			puts "#{indent}Globals"
			@globals.list(compact,"\t"+indent)
			puts "#{indent}Clients"
			@clients.each_pair { |client,conf|
				puts "#{indent}#{client}:"
				conf.list(compact, "\t"+indent)
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

		#Rb2Globals.dump_defaults("Rb2Globals")

		json=load_config(conf)
		#@@log.debug "json=#{json}"
		config=parse_config(json)
		config[:globals]=Rb2Globals.from_hash(config[:globals])
		clients = config[:clients]||{}
		cc = {}

		#Rb2Conf.dump_defaults("Rb2Conf")

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
			@@log.info "Write json config to #{@config_file}"
			fd.puts(json)
		}
	rescue => e
		e.backtrace.each { |b|
			puts b
		}
		raise "save_config_json: Unexpected exception: #{e.to_s}"
	end

	def save_config(opts={:force=>false})
		conf=opts[:conf]
		@config_file = conf unless conf.nil?
		create_config_dir
		return unless @updated == true
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


