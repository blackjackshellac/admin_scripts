
class RsyncError < StandardError
end

class Rsync
	@@log = Logger.new(STDERR)
	@@tmp = "/var/tmp"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp] if opts.key?(:tmp)

		@@runtime=opts[:runtime]||Time.now

		@@logdir=opts[:logdir]
		raise "Logdir not set" if @@logdir.nil?
		@@logformat=opts[:logformat]
		raise "Logformat not set" if @@logformat.nil?

		@@log.info FileUtils.mkdir_p(@@logdir)
		@@logfile=File.join(@@logdir, @@runtime.strftime(@@logformat))
		@@log = Logger.set_logger(@@logfile, Logger::INFO)
	end

	attr_reader :rb2conf, :client, :client_config, :sshopts, :excludes, :includes, :conf
	def initialize(rb2conf, opts)
		@rb2conf=rb2conf
		@rb2conf_clients=@rb2conf.clients

		globals=@rb2conf.globals #:dest, :logdir, :logformat, :syslog, :email, :smtp
		@globals=globals
		@dest=globals.dest
		#@logdir=globals.logdir
		#@logformat=globals.logformat
		@syslog=globals.syslog
		@email=globals.email
		@smtp=globals.smtp
		@conf=globals.conf

		@verbose = opts[:verbose]

		# rubac.20170221.pidora.excl
		#
		#
		# /mnt/backup/rubac/pidora/rubac.20170221
		@filestamp=@@runtime.strftime("rb2.%Y%m%d")

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

	BACKUP_DIR_RE=/(?<rb2>rb2|rubac).(?<date>\d+)(\.(?<num>\d+))?/
	def sort_dirs(dirs)
		@@log.info "Dirs before sort"+dirs.inspect
		dirs.sort! { |d1,d2|
			m1=d1.match(BACKUP_DIR_RE)
			raise "Regular expression match failed for directory d1=#{d1}" if m1.nil?
			m2=d2.match(BACKUP_DIR_RE)
			raise "Regular expression match failed for directory d2=#{d2}" if m2.nil?
			date1=m1[:date]
			date2=m2[:date]

			num1=m1[:num]
			num2=m2[:num]

			if date1.eql?(date2)
				if num1.nil? && num2.nil?
					raise "this shouldn't happen" # date2 <=> date1
				elsif num1.nil?
					puts "date1=#{date1.inspect} num1=#{num1.inspect} date2=#{date2.inspect} num2=#{num2.inspect}"
					+1
				elsif num2.nil?
					puts "date1=#{date1.inspect} num1=#{num1.inspect} date2=#{date2.inspect} num2=#{num2.inspect}"
					-1
				else
					num2.to_i <=> num1.to_i
				end
			else
				date2 <=> date1
			end
		}
		@@log.info "Dirs after sort"+dirs.inspect
		dirs
	end

	def list_bdest(bdir)
		dirs=[]
		FileUtils.chdir(bdir) {
			@@log.debug "Scanning backup destination directory: "+bdir
			Dir.glob("*") { |dir|
				#puts "glob=#{dir}"
				next unless File.directory?(dir)
				next if dir[BACKUP_DIR_RE].nil?
				dirs << dir
			}
		}
		sort_dirs(dirs)
	end

	def find_latest(dirs)
		latest=nil
		unless dirs.empty?
			idx=@filestamp.eql?(dirs[0]) ? 1 : 0
			latest=dirs[idx].nil? ? nil : File.join(@bdir, dirs[idx])
			raise RsyncError, "Latest is not a directory: #{latest}" unless latest.nil? || File.directory?(latest)
		end
		latest
	end

	def setup(client)
		@@log.debug "client="+client.inspect
		@@log.debug "client_config="+@rb2conf_clients.inspect
		# rubac.20170221.pidora
		@client=client.to_s
		@bdir=File.join(@dest, @client)
		FileUtils.mkdir_p(@bdir)
		@bdest=File.join(@bdir, @filestamp)

		@dirs=list_bdest(@bdir)
		@latest = find_latest(@dirs)

		puts "latest=#{@latest}"

		puts FileUtils.mkdir_p(@bdest, {:noop=>false, :verbose=>true})

		@client_config=@rb2conf_clients[client.to_sym]
		if @client_config.nil?
			@@log.warn "Client not found in config #{client}"
			@@log.debug "Clients: #{@rb2conf_clients.keys}"
		else
			@client=client
			@excludes=create_excludes_arr
			@includes=create_includes_arr
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

	def quote_str(str, pad=false)
		q=str[/\s/].nil? ? "" : "\""
		p=pad ? " " : ""
		"#{p}#{q}#{str}#{q}#{p}"
	end

	def get_cmd(opts)
		cmd =  "rsync -r #{@sshopts[:global]} " # #{@sshopts["#{host}"]}"
		cmd << " --dry-run " if opts[:dryrun]
		cmd << " --delete" if @action == :run

		# write the excludes to a file and use --exclude-from
		cmd << create_excludes_from

		# with files-from we use "/" as the src (or host:/ for remote)
		#src = "/"
		#src = " #{@address}:#{src}" if @address != "localhost" and @address != "127.0.0.1"
		# cmd << " --files-from=\"#{incl}\""

		cmd << " --link-dest=#{quote_str(@latest)}" unless @latest.nil?

		cmd << create_includes_str
		cmd << quote_str(@bdest, true)
		cmd
	end

	def go(opts)
		#puts @client_config.inspect
		conf=@client_config.conf
		# :opts, :includes, :excludes, :nincrementals, :compress
		#opts=conf.opts

		@nincrementals=conf.nincrementals

		case @action
		when :run
			@@log.info "#{@action.to_s.capitalize} backup #{@client}: includes=#{@includes.inspect} excludes=#{@excludes.inspect}"
		when :update
			@@log.info "#{@action.to_s.capitalize} backup #{@client}: includes=#{@includes.inspect} excludes=#{@excludes.inspect}"
		else
			raise RsyncError, "Unknown action in Rsync.go: #{@action}"
		end
		cmd = get_cmd(opts)
		@@log.info "cmd=[%s]" % get_cmd(opts)
		opts[:strip]=true
		opts[:lines]=nil
		opts[:out]=@verbose ? $stdout : nil
		opts[:log]=@@log

		exit_status = Runner::run3!(cmd, opts)
		case exit_status
		when 23,24
			@@log.info "Rsync command success exit_status = #{exit_status}: [#{cmd}]"
		when 0
			@@log.info "Rsync command success: [#{cmd}]"
		else
			@@log.error "Rsync failed, exit_status == #{exit_status}"
			if @action == :run
				es=Runner::run3!("rm -rvf #{@bdest}/", opts)
				@@log.error "Failed to remove failed backup in #{@bdest}" unless es == 0
			end
		end
		puts FileUtils.rmdir(@bdest, {:verbose=>true})
	end

	def test_clients(clients)
		return unless clients.empty?
		c=@rb2conf_clients.keys
		msg=c.empty? ? "No clients configured" : "No clients specified, use --all to #{@action.to_s} backup #{@rb2conf.clients.keys.inspect}"
		$log.die msg
	end

	DEF_OPTS={
		:all=>false,
		:strip=>true,
		:lines=>[],
		:out=>$stdout,
		:log=>nil
	}
	def run(clients, opts=DEF_OPTS)
		@action=__method__.to_sym
		clients = @rb2conf_clients.keys if clients.empty? && opts[:all]
		test_clients(clients)
		clients.each { |client|
			next unless setup(client)
			go(opts)
		}
	end

	def update(clients, opts=DEF_OPTS)
		@action=__method__.to_sym
		clients = @rb2conf_clients.keys if clients.empty? && opts[:all]
		test_clients(clients)
		clients.each { |client|
			next unless setup(client)
			go(opts)
		}
	end

	def create_includes_arr
		addr=@client_config.address
		cc=@client_config.conf

		# prefix is empty for localhost, otherwise it is hostname:
		prefix=(addr.nil? || addr.eql?("localhost") || addr.eql?("127.0.0.1")) ? "" : "#{addr}:"

		includes=[]
		# global includes
		@conf.includes.each { |inc|
			includes << (prefix+quote_str(inc))
		}
		# client includes
		cc.includes.each { |inc|
			includes << (prefix+quote_str(inc))
		}
		includes.uniq!
		includes
	end

	def create_excludes_arr
		cc=@client_config.conf
		excludes=[]
		# global excludes
		excludes.concat(@conf.excludes)
		# client excludes
		excludes.concat(cc.excludes)
		excludes.uniq!
		excludes
	end

	def create_includes_str
		raise RsyncError, "Nothing to backup, includes is empty" if @includes.empty?

		s=""
		@includes.each { |inc|
			s << " #{inc} "
		}
		" #{s} "
	end

	def create_excludes_from
		return "" if @excludes.empty?
		# /tmp/rb.20170221.pidora.excl
		excl = File.join(@@tmp, File.basename(@filestamp) + ".#{@client}.excl")
		File.open( excl, "w" ) { |fd|
			@excludes.each { |x|
				fd.puts( x )
			}
		}
		" --exclude-from=#{quote_str(excl)} "
	end

end

