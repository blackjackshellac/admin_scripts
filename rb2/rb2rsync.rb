
require 'mail'

class Rb2RsyncError < StandardError
end

class Rb2Maillog
	RB2MAILLOGFMT="rb2_%Y%m%d_%H%M%S.txt"
	@@log = Logger.new(STDERR)
	@@tmp = "/var/tmp/rb2"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp]
		Mail.defaults do
			delivery_method :smtp, { address: "localhost", openssl_verify_mode: "none" }
		end
	end

	attr_reader :file
	def initialize(opts)
		@runtime=opts[:runtime]
		@file = File.join(@@tmp, @runtime.strftime(RB2MAILLOGFMT))
		@client = nil
		@compress = true
	end

	def open(opts, &block)
		@@log.debug "Opening #{@file}"
		@fd = File.open(@file, "w+")
		opts[:maillog]=self
		return @fd unless block_given?
		@@log.debug "Yeilding #{@fd}"
		yield(@fd)
	ensure
		@@log.debug "Closing #{@file}"
		@fd.close
	end

	def set_client(c)
		@client=c
	end

	def fmt(type, msg)
		ts=Time.now.strftime("%Y%m%d_%H%M%S")
		c=@client.nil? ? " " : " [#{@client}] "
		"#{type}#{c}#{ts}: #{msg}"
	end

	def self.get_separator(msg)
		sep=""+SEP
		unless msg.nil?
			msg.strip!
			msg=" #{msg} "
			ml=msg.length
			sl=sep.length
			o=(sl-ml)/2.floor
			sep[o, ml]=msg if o > 0
		end
		sep
	end

	SEP_LENGTH=50
	SEP="+"*SEP_LENGTH
	def separator(msg=nil, opts={})
		fmsg = fmt("I", Rb2Maillog.get_separator(msg))
		mputs fmsg, opts
	end

	def mputs(fmsg, opts={})
		puts fmsg if opts[:echo]
		@fd.puts fmsg unless @fd.nil?
	end

	def info(msg, opts={})
		opts[:logger].info msg unless opts[:logger].nil?

		fmsg = fmt("I", msg)
		mputs fmsg, opts
	end

	def error(msg, opts={})
		opts[:logger].error msg unless opts[:logger].nil?

		fmsg = fmt("E", msg)
		mputs fmsg, opts
	end

	def compress
		puts %x/gzip #{@file}/
		@file=@file+".gz"
	end

	def get_body
		errs=%x/grep -v ^I #{@file}/.strip
		errors=errs.empty? ? "" : "\nPossible errors:\n#{errors}"
		cmd="tail -50 #{@file}"
		tail = %x/#{cmd}/.strip
		<<-BODY
See attachment #{@file}

$ #{cmd}
#{tail}
#{errors}
BODY
	end

	def mail(opts)
		body = get_body

		compress if @compress

		@@log.info "Mailing log file #{@file}"

		subj = opts[:subject]
		from = opts[:email_from]
		to   = opts[:email_to]
		mailer = Mail.new do
			from     from
			to       to
			subject  subj
			body     body
		end

		mailer.add_file(@file)
		mailer.charset = "UTF-8"

		@@log.debug mailer.to_s
		mailer.deliver
	rescue => e
		@@log.error "Failed to mail result: #{opts.inspect} [#{e.to_s}]"
	end
end

class Rb2Rsync
	@@log = Logger.new(STDERR)
	@@tmp = "/var/tmp/rb2"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp] if opts.key?(:tmp)
		opts[:tmp]=@@tmp

		@@log.info FileUtils.mkdir_p(@@tmp)

		raise "opts :runtime not set" if opts[:runtime].nil?
		@@runtime=opts[:runtime]

		@@logdir=opts[:logdir]
		raise "Logdir not set" if @@logdir.nil?
		@@logformat=opts[:logformat]
		raise "Logformat not set" if @@logformat.nil?

		@@logname=@@runtime.strftime(@@logformat)
		@@logfile=File.join(@@logdir, @@logname)
		@@log = Logger.set_logger(@@logfile, Logger::INFO)

		Rb2Maillog.init(opts)
		@@maillog = Rb2Maillog.new(opts)

		Rb2Rsync.info(FileUtils.mkdir_p(@@logdir), { :echo => true, :logger=>@@log })
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
		@email=globals.email.join(",")
		@smtp=globals.smtp
		@conf=globals.conf

		@sshopts=@conf.sshopts

		#Mail.defaults do
		#	delivery_method :smtp, address: @smtp
		#end

		@verbose = opts[:verbose]

		# rubac.20170221.pidora.excl
		#
		#
		# /mnt/backup/rubac/pidora/
		# rubac.20170221
		@dirstamp=@@runtime.strftime("rb2.%Y%m%d")

		#@sshopts = {
		#	:global  => "-a -v -v",
		#	:restore => "-a -r -v -v"
		#}
		#if ENV['RUBAC_SSHOPTS']
		#	@sshopts[:global] = ENV['RUBAC_SSHOPTS']
		#else
		#	@sshopts[:global] = "-a -v -v"
		#end
		#@sshopts[:restore] = "-a -r -v -v"
		## don't --delete on update command, add this on run only
		#@sshopts[:global] << " --relative --delete-excluded --ignore-errors --one-file-system"
		#@sshopts[:restore] << " --relative --one-file-system"
		#@sshopts[:global] << " --xattrs"
		#"-a -v -v --relative --delete-excluded --ignore-errors --one-file-system --xattrs"
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
					@@log.debug "date1=#{date1.inspect} num1=#{num1.inspect} date2=#{date2.inspect} num2=#{num2.inspect}"
					+1
				elsif num2.nil?
					@@log.debug "date1=#{date1.inspect} num1=#{num1.inspect} date2=#{date2.inspect} num2=#{num2.inspect}"
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

	def list_bdir(bdir)
		dirs=[]
		FileUtils.chdir(bdir) {
			@@log.debug "Scanning backup destination directory: "+bdir
			Dir.glob("*") { |dir|
				#@@log.debug "glob=#{dir}"
				next unless File.directory?(dir)
				next if dir[BACKUP_DIR_RE].nil?
				dirs << dir
			}
		}
		sort_dirs(dirs)
	end

	def find_latest_bdest(dirs, action)
		dirs=[] if dirs.nil?
		case action
		when :run
			bdest = File.join(@bdir, @dirstamp)
			# don't use current backup directory "@dirstamp" for latest from list of dirs
			idx=@dirstamp.eql?(dirs[0]) ? 1 : 0
			latest=dirs[idx].nil? ? nil : File.join(@bdir, dirs[idx])
		when :update,:latest
			# don't use current backup directory "@dirstamp" for latest from list of dirs
			idx=@dirstamp.eql?(dirs[0]) ? 1 : 0

			raise Rb2RsyncError, "Backup destination for update not found" if dirs[0].nil?
			bdest = dirs[0].nil? ? nil : File.join(@bdir, dirs[0])
			latest=nil
		else
			raise Rb2RsyncError, "Unknown backup action: #{action}"
		end
		raise Rb2RsyncError, "Latest is not a directory: #{latest}" unless latest.nil? || File.directory?(latest)
		[latest,bdest]
	end

	def find_latest(dirs=nil)
		dirs = list_bdir(@bdir) if dirs.nil?

		latest=nil
		unless dirs.empty?
			# don't use current backup directory for latest from list of dirs
			idx=@dirstamp.eql?(dirs[0]) ? 1 : 0
			latest=dirs[idx].nil? ? nil : File.join(@bdir, dirs[idx])
			raise Rb2RsyncError, "Latest is not a directory: #{latest}" unless latest.nil? || File.directory?(latest)
		end
		latest
	end

	def setup(client, action)
		@client=client.to_s

		# maillog adds client string to output
		@@maillog.set_client(@client)
		Rb2Rsync.separator("Setup #{@client}", {:echo => true})

		@@log.debug "client="+client.inspect
		@@log.debug "client_config="+@rb2conf_clients.inspect
		# rubac.20170221.pidora

		@bdir=File.join(@dest, @client)
		Rb2Rsync.info(FileUtils.mkdir_p(@bdir), { :echo => true, :logger=>@@log } ) unless File.exists?(@bdir)

		@dirs = list_bdir(@bdir)

		@latest,@bdest=find_latest_bdest(@dirs, action)

		Rb2Rsync.info(FileUtils.mkdir_p(@bdest), { :echo => true, :logger=>@@log }) unless File.exists?(@bdest)

		FileUtils.chmod(0755, @bdest)

		Rb2Rsync.info("bdest  #{@bdest}", { :echo => true })
		Rb2Rsync.info("latest #{@latest}", { :echo => true }) unless @latest.nil?

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

	def get_cmd(opts, client_conf)
                sshopts=client_conf.sshopts.nil? ? @sshopts : client_conf.sshopts
		cmd =  "rsync -r #{sshopts} " # #{@sshopts["#{host}"]}"
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

	DEF_OUT_OPTS={:echo=>false, :logger=>nil}
	def self.info(msgs, opts=DEF_OUT_OPTS)
		opts=DEF_OUT_OPTS.merge(opts)
		msgs = msgs.join("\n") if msgs.class == Array
		msgs.chomp
		opts[:logger]=@@log
		msgs.split(/\n/).each { |msg|
			@@maillog.info(msg, opts)
		}
	end

	def self.error(msgs, opts=DEF_OUT_OPTS)
		opts=DEF_OUT_OPTS.merge(opts)
		msgs = msgs.join("\n") if msgs.class == Array
		msgs.chomp
		opts[:logger]=@@log
		msgs.split(/\n/).each { |msg|
			@@maillog.error(msg, opts)
		}
	end

	def self.separator(msg, opts=DEF_OUT_OPTS)
		opts=DEF_OUT_OPTS.merge(opts)
		opts[:logger]=@@log
		opts[:echo]=true
		@@maillog.separator(msg, opts)
	end

	def link_latest(bdest=nil)
		bdest = find_latest(@dirs) if bdest.nil?
		return if bdest.nil?
		base=File.dirname(bdest)
		FileUtils.chdir(base) {
			FileUtils.rm_f "latest" if File.symlink?("latest")
			FileUtils.ln_s bdest, "latest"
		}
	end

	def remove_backup(bdest, opts)
		rm_opts=@verbose ? "-rvf" : "-rf"

		raise Rb2RsyncError, "bdest cannot be empty!" if bdest.empty? || bdest.nil?

		cmd="rm #{rm_opts} #{bdest}/"
		Rb2Rsync.info "Removing backup: #{cmd}", :echo=>true
		es=Runner::run3!(cmd, opts)
		raise Rb2RsyncError, "Failed to remove backup: #{bdest}" unless es == 0
	end

	def go(opts)
		#@@log.debug @client_config.inspect
		conf=@client_config.conf
		# :sshopts, :includes, :excludes, :nincrementals, :compress

		@nincrementals=conf.nincrementals

		case @action
		when :run
			Rb2Rsync.info "#{@action.to_s.capitalize} backup #{@client}: includes=#{@includes.inspect} excludes=#{@excludes.inspect}"
		when :update
			Rb2Rsync.info "#{@action.to_s.capitalize} backup #{@client}: includes=#{@includes.inspect} excludes=#{@excludes.inspect}"
		else
			raise Rb2RsyncError, "Unknown action in Rb2Rsync.go: #{@action}"
		end

		cmd = get_cmd(opts, conf)
		opts[:strip]=true
		opts[:lines]=nil
		opts[:out]=@verbose ? $stdout : nil
		opts[:log]=@@log
		opts[:filter]=@verbose ? nil : /\sis\suptodate$/

		Rb2Rsync.info("Running #{cmd}", {:echo => true})
		exit_status = Runner::run3!(cmd, opts)
		case exit_status
		when 23,24
			Rb2Rsync.info "Rb2Rsync command success exit_status = #{exit_status}: [#{cmd}]"
			link_latest(@bdest)
		when 0
			Rb2Rsync.info "Rb2Rsync command success: [#{cmd}]"
			link_latest(@bdest)
		else
			Rb2Rsync.error "Rb2Rsync failed, exit_status == #{exit_status}"
			remove_backup(@bdest, opts) if @action == :run
			link_latest
		end
		begin
			FileUtils.rmdir(@bdest)
		rescue Errno::EACCES => e
		rescue Errno::ENOTEMPTY => e
			# ignore if directory is not empty
		rescue => e
			throw e
		end
		exit_status
	end

	def test_clients(clients)
		@@log.debug "Running test_clients on #{clients.inspect}"
		if clients.empty?
			c=@rb2conf_clients.keys
			error c.empty? ? "No clients configured" : "No clients specified, use --all to #{@action.to_s} backup #{@rb2conf.clients.keys.inspect}"
		else
			failed = false
			#ssh -q -o "BatchMode=yes" -i ~/.ssh/id_rsa "$c" exit
			clients.each { |client|
				Rb2Rsync.separator("Testing client #{client}")
				c=client.to_s
				@@log.debug @rb2conf_clients.inspect
				cc=@rb2conf_clients[client.to_sym]
				a=cc.get_ssh_address
				next if a.nil?
				cmd = %Q[ssh -q -o "BatchMode=yes" -i ~/.ssh/id_rsa "#{a}" exit]
				Rb2Rsync.info cmd
				es = Runner::run3!(cmd, {:strip=>true, :out=>$stdout, :log=>@@log})
				if es != 0
					msg="Failed to ssh to client #{c} with address #{a}: error=#{es}"
					Rb2Rsync.error msg, :echo=>true
					raise msg
					failed = true
				else
					@@log.debug "Success: #{cmd}"
				end
			}
			if failed
				@@log.error "Failed to test clients"
				clients.clear
			end
		end
		clients
	end

	def df_h
		raise "bdest is nil" if @bdest.nil?
		@@maillog.set_client(nil)
		Rb2Rsync.info("$ df -h #{@bdest}\n#{%x/df -h #{@bdest}/}", {:echo=>true}) if File.exist?(@bdest)
	end

	# initialize if start==true
	def log_runtime(start=false)
		if start
			@starttime=Time.now
			Rb2Rsync.info(">> Starting run at #{@starttime}")
		else
			@@maillog.set_client(nil)
			runtime=Time.now.to_i-@starttime.to_i
			Rb2Rsync.info(">> Run time = %.1f seconds" % runtime, {:echo=>true})
		end
	end

	DEF_OPTS={
		:all=>false,
		:strip=>true,
		:lines=>[],
		:out=>$stdout,
		:log=>nil
	}
	def run(clients, opts=DEF_OPTS)
		clients = @rb2conf_clients.keys if clients.empty? && opts[:all]
		@@maillog.open(opts) { |maillog|
			@action=__method__.to_sym
			log_runtime(true)
			test_clients(clients).each { |client|
				next unless setup(client, @action)
				go(opts)
				# TODO test incrementals for client
			}
			df_h
			log_runtime
		}
		mopts = {
			:subject => "Run backup finished: #{clients.join(',')}",
			:email_from => @email,
			:email_to   => @email
		}
		@@maillog.mail(mopts)
	end

	def update(clients, opts=DEF_OPTS)
		clients = @rb2conf_clients.keys if clients.empty? && opts[:all]
		@@maillog.open(opts) { |maillog|
			@action=__method__.to_sym
			log_runtime(true)
			test_clients(clients).each { |client|
				@@log.debug "Setup #{client}"
				next unless setup(client, @action)
				go(opts)
				# TODO test incrementals for client
			}
			df_h
			log_runtime
		}
		mopts = {
			:subject => "Update backup finished: #{clients.join(',')}",
			:email_from => @email,
			:email_to   => @email
		}
		@@maillog.mail(mopts)
	end

	def latest(clients, opts=DEF_OPTS)
		clients = @rb2conf_clients.keys if clients.empty? && opts[:all]
		clients.each { |client|
			@@log.debug "Setup #{client}"
			@action=__method__.to_sym
			client_config = setup(client, @action)
			next if client_config.nil?
			@@log.info "Client #{client}: #{@latest}"
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
		raise Rb2RsyncError, "Nothing to backup, includes is empty" if @includes.empty?

		s=""
		@includes.each { |inc|
			s << " #{inc} "
		}
		" #{s} "
	end

	def create_excludes_from
		return "" if @excludes.empty?
		# /tmp/rb.20170221.pidora.excl
		excl = File.join(@@tmp, File.basename(@dirstamp) + ".#{@client}.excl")
		File.open( excl, "w" ) { |fd|
			@excludes.each { |x|
				fd.puts( x )
			}
		}
		" --exclude-from=#{quote_str(excl)} "
	end

end

