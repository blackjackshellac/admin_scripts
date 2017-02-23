
require 'logger'

class RsyncError < StandardError
end

class Rsync
	@@log = Logger.new(STDERR)
	@@tmp = "/var/tmp"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp] if opts.key?(:tmp)
	end

	attr_reader :rb2conf, :client, :client_config, :sshopts, :excludes, :includes, :conf
	def initialize(rb2conf)
		@rb2conf=rb2conf

		globals=@rb2conf.globals #:dest, :logdir, :logformat, :syslog, :email, :smtp
		@globals=globals
		@dest=globals.dest
		@logdir=globals.logdir
		@logformat=globals.logformat
		@syslog=globals.syslog
		@email=globals.email
		@smtp=globals.smtp
		@conf=globals.conf

		# rubac.20170221.pidora.excl
		@bdest=Time.new.strftime(@logformat)

		@sshopts = {}
		if ENV['RUBAC_SSHOPTS']
			@sshopts[:global] = ENV['RUBAC_SSHOPTS']
		else
			@sshopts[:global] = "-a -v -v"
			@sshopts[:restore] = "-a -r -v -v"
		end
		# don't --delete on update command, add this on run only
		@sshopts[:global] << " --relative --delete-excluded --ignore-errors --one-file-system"
		@sshopts[:restore] << " --relative --one-file-system"
		@sshopts[:global] << " --xattrs"
	end

	def setup(conf_clients, client)
		@client_config=conf_clients[client]
		if @client_config.nil?
			@@log.warn "Client not found in config #{client}"
			@@log.debug "Clients: #{conf_clients.keys}"
		else
			@client=client
			@excludes=create_excludes
			@includes=create_includes
		end
		return @client_config.nil? ? false : true
	end

	# rsync
	#    -r -a -v -v --relative --delete-excluded --ignore-errors --one-file-system --xattrs --acls --xattrs
	#    --exclude-from="/tmp/rubac.20170221.pidora.excl"
	#    pidora:/home/pi
	#    pidora:/etc
	#    pidora:/root
	#
	#    /mnt/backup/rubac/pidora/rubac.20170221
	#
	#
	#$ ls -lrt
	#total 4
	#drwxr-xr-x 1 root root 50 Jan 31 13:34 rubac.20170131
	#drwxr-xr-x 1 root root 50 Feb 21 11:17 rubac.20170221
	#lrwxrwxrwx 1 root root 39 Feb 22 16:18 latest -> /mnt/backup/rubac/pidora/rubac.20170221

	def get_cmd(action, src, ldest, host)
		cmd =  "rsync -r #{@sshopts[:global]} #{@sshopts["#{host}"]}"
		cmd << " --delete" if action == :run
		cmd << " --link-dest=#{ldest}" if ldest

		# write the excludes to a file and use --exclude-from
		cmd << create_excludes_from

		# with files-from we use "/" as the src (or host:/ for remote)
		#src = "/"
		#src = " #{@address}:#{src}" if @address != "localhost" and @address != "127.0.0.1"
		# cmd << " --files-from=\"#{incl}\""

		cmd << " #{src}"
		cmd << " #{@bdest}"
		cmd
	end

	def go(action)
		#puts @client_config.inspect
		conf=@client_config.conf
		# :opts, :includes, :excludes, :nincrementals, :compress
		opts=conf.opts

		@nincrementals=conf.nincrementals

		case action
		when :run
			@@log.info "#{action.to_s.capitalize} backup #{@client}: includes=#{@includes.inspect} excludes=#{@excludes.inspect}"
		when :update
			@@log.info "#{action.to_s.capitalize} backup #{@client}: includes=#{@includes.inspect} excludes=#{@excludes.inspect}"
		else
			raise RsyncError, "Unknown action in Rsync.go: #{action}"
		end
		@@log.info "cmd="+get_cmd(action, "src", "latest", @client)
	end

	def test_clients(clients, action)
		return unless clients.empty?
		c=@rb2conf.clients.keys
		msg=c.empty? ? "No clients configured" : "No clients specified, use --all to #{action.to_s} backup #{@rb2conf.clients.keys.inspect}"
		$log.die msg
	end

	def run(clients, opts={:all=>false})
		action=__method__.to_sym
		clients = @rb2conf.clients.keys if clients.empty? && opts[:all]
		test_clients(clients, action)
		clients.each { |client|
			next unless setup(@rb2conf.clients, client)
			go(action)
		}
	end

	def update(clients, opts={:all=>false})
		action=__method__.to_sym
		clients = @rb2conf.clients.keys if clients.empty? && opts[:all]
		test_clients(clients, action)
		clients.each { |client|
			next unless setup(@rb2conf.clients, client)
			go(action)
		}
	end

	def create_includes
		addr=@client_config.address
		cc=@client_config.conf

		# prefix is empty for localhost, otherwise it is hostname:
		prefix=(addr.nil? || addr.eql?("localhost") || addr.eql?("127.0.0.1")) ? "" : "#{addr}:"

		includes=[]
		# global includes
		@conf.includes.each { |inc|
			includes << prefix+inc
		}
		# client includes
		cc.includes.each { |inc|
			includes << prefix+inc
		}
		includes.uniq!
		includes
	end

	def create_excludes
		cc=@client_config.conf
		excludes=[]
		# global excludes
		excludes.concat(@conf.excludes)
		# client excludes
		excludes.concat(cc.excludes)
		excludes.uniq!
		excludes
	end

	def create_excludes_from
		return "" if @excludes.empty?
		# /tmp/rb.20170221.pidora.excl
		excl = File.join(@@tmp, File.basename(@bdest) + ".#{@client}.excl")
		File.open( excl, "w" ) { |fd|
			@excludes.each { |x|
				fd.puts( x )
			}
		}
		" --exclude-from=\"#{excl}\" "
	end

end

