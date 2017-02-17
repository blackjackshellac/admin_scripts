
require 'logger'

class RsyncError < StandardError
end

class Rsync
	@@log = Logger.new(STDERR)
	@@tmp = "/"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp] if opts.key?(:tmp)
	end

	attr_reader :rb2conf, :client, :client_config, :sshopts, :excludes, :includes
	def initialize(rb2conf)
		@rb2conf=rb2conf

		globals=@rb2conf.globals #:dest, :logdir, :logformat, :syslog, :email, :smtp
		@dest=globals.dest
		@logdir=globals.logdir
		@logformat=globals.logformat
		@syslog=globals.syslog
		@email=globals.email
		@smtp=globals.smtp

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
			create_excludes
			create_includes
		end
		return @client_config.nil? ? false : true
	end

	def get_cmd(src, ldest, bdest, host)
		cmd =  "rsync -r #{@sshopts[:global]} #{@sshopts["#{host}"]}"
		cmd << " --delete" if not @options.update
		cmd << " --link-dest=#{ldest}" if ldest

		# write the excludes to a file and use --exclude-from
		if @excludes.length > 0
			excl = nil
			excl = File.join(@@tmp, File.basename(bdest) + ".#{host}.excl")
			File.open( excl, "w" ) { |exclf|
				@excludes.each { |x|
					exclf.puts( x )
				}
			}
			cmd << " --exclude-from=\"#{excl}\""
		end

		# with files-from we use "/" as the src (or host:/ for remote)
		#src = "/"
		#src = " #{@address}:#{src}" if @address != "localhost" and @address != "127.0.0.1"
		# cmd << " --files-from=\"#{incl}\""

		cmd << " #{src}"
		cmd << " #{bdest}"
		cmd
	end

	def go(action)
		#puts @client_config.inspect
		addr=@client_config.address
		conf=@client_config.conf
		# :opts, :includes, :excludes, :nincrementals, :compress
		opts=conf.opts
		includes=conf.includes
		excludes=conf.excludes
		nincrementals=conf.nincrementals

		case action
		when :run
			@@log.info "#{action.to_s.capitalize} backup #{@client}: includes=#{includes.inspect} excludes=#{excludes.inspect}"
		when :update
			@@log.info "#{action.to_s.capitalize} backup #{@client}: includes=#{includes.inspect} excludes=#{excludes.inspect}"
		else
			raise RsyncError, "Unknown action in Rsync.go: #{action}"
		end
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

	def create_excludes
		excludes=Array.new(@client_config.conf.excludes)
		excludes.concat(@rb2conf.globals.conf.excludes)
		excludes.uniq!
		@@log.debug "excludes="+excludes.join(",")
		@excludes=excludes
	end

	def create_includes
		includes=Array.new(@client_config.conf.includes)
		includes.concat(@rb2conf.globals.conf.includes)
		includes.uniq!
		@@log.debug "includes="+includes.join(",")
		@includes=includes
	end
end

