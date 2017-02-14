
require 'logger'

class Rsync
	@@log = Logger.new(STDERR)
	@@tmp = "/"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp] if opts.key?(:tmp)
	end

	attr_reader :conf, :client, :client_config, :sshopts, :excludes, :includes
	def initialize(conf)
		@conf=conf

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

	def setup(clients, client, client_conf)
		unless clients.include?(client.to_s)
			@@log.debug "Ignoring client #{client}"
			return false
		end

		@client=client
		@client_config=client_conf
		create_excludes
		create_includes

		return true
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
		case action
		when :RUN
			@@log.info "Run backup #{@client}"
		when :UPDATE
			@@log.info "Update backup #{@client}"
		else
			@@log.die "Unknown action in Rsync.go: #{action}"
		end
	end

	def run(clients)
		@conf.clients.each_pair { |client,client_conf|
			next unless setup(clients, client, client_conf)
			go(:RUN)
		}
	end

	def update(clients)
		@conf.clients.each_pair { |client,client_conf|
			next unless setup(clients, client, client_conf)
			go(:UPDATE)
		}
	end

	def create_excludes
		excludes=Array.new(@client_config.conf.excludes)
		excludes.concat(@conf.globals.conf.excludes)
		excludes.uniq!
		@@log.debug "excludes="+excludes.join(",")
		@excludes=excludes
	end

	def create_includes
		includes=Array.new(@client_config.conf.includes)
		includes.concat(@conf.globals.conf.includes)
		includes.uniq!
		@@log.debug "includes="+includes.join(",")
		@includes=includes
	end
end

