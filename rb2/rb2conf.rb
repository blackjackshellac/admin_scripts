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
	attr_accessor :opts, :includes, :excludes, :nincrementals, :compress

	def self.from_hash(h)
		h={} if h.nil?
		rb2conf = Rb2Conf.new
		rb2conf.opts = h[:opts]||""
		rb2conf.includes = h[:includes]||[]
		rb2conf.excludes = h[:excludes]||[]
		rb2conf.nincrementals = h[:nincrementals]||5
		rb2conf.compress = h[:compress]||false
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
	attr_accessor :address, :conf

	def self.from_hash(h)
		h={} if h.nil?

		rb2client = Rb2Client.new
		rb2client.address = h[:address]||"localhost"
		rb2client.conf = Rb2Conf.from_hash(h[:conf])
		rb2client
	end

	def to_hash
		{
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
			cc[client.to_sym]=Rb2Client.from_hash(conf)
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

