
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
	end

	attr_reader :file
	def initialize(opts)
		@runtime=opts[:runtime]
		@file = File.join(@@tmp, @runtime.strftime(RB2MAILLOGFMT))
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

	def fmt(type, msg)
		ts=Time.now.strftime("%Y%m%d_%H%M%S")
		@fd.puts "#{type} #{ts}: #{msg}"
	end

	SEP_LENGTH=50
	SEP="+"*SEP_LENGTH
	def separator(msg=nil)
		sep=""+SEP
		unless msg.nil?
			msg.strip!
			msg=" #{msg} "
			ml=msg.length
			sl=sep.length
			o=(sl-ml)/2.floor
			sep[o, ml]=msg if o > 0
		end
		@fd.puts sep
	end

	def info(msg)
		fmt("I", msg)
	end

	def error(msg)
		fmt("E", msg)
	end

	def mail(opts)
		subj = opts[:subject]
		from = opts[:email_from]
		to   = opts[:email_to]
		body = File.read(@file)
		mailer = Mail.new do
			from     from
			to       to
			subject  subj
			body     body
			#add_file :filename => File.basename(@file), :content => File.read(@file)
		end

		@@log.debug mailer.to_s
		mailer.deliver
	rescue => e
		raise "Failed to mail result: #{opts.inspect} [#{e.to_s}]"
	end
end

class Rb2Rsync
	@@log = Logger.new(STDERR)
	@@tmp = "/var/tmp/rb2"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
		@@tmp = opts[:tmp] if opts.key?(:tmp)
		opts[:tmp]=@@tmp

		FileUtils.mkdir_p(@@tmp)

		raise "opts :runtime not set" if opts[:runtime].nil?
		@@runtime=opts[:runtime]

		@@logdir=opts[:logdir]
		raise "Logdir not set" if @@logdir.nil?
		@@logformat=opts[:logformat]
		raise "Logformat not set" if @@logformat.nil?

		@@log.info FileUtils.mkdir_p(@@logdir)
		@@logname=@@runtime.strftime(@@logformat)
		@@logfile=File.join(@@logdir, @@logname)
		@@log = Logger.set_logger(@@logfile, Logger::INFO)

		Rb2Maillog.init(opts)
		@@maillog = Rb2Maillog.new(opts)
	end

	attr_reader :rb2conf, :client, :client_config, :sshopts, :excludes, :includes, :conf
	def initialize(rb2conf, opts)
		@rb2conf=rb2conf
		@rb2conf_clients=@rb2conf.clients

		globals=@rb2conf.globals #:dest, :logdir, :logformat, :syslog, :email, :smtp
		puts "globals="+globals.inspect
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
			# don't use current backup directory for latest from list of dirs
			idx=@dirstamp.eql?(dirs[0]) ? 1 : 0
			latest=dirs[idx].nil? ? nil : File.join(@bdir, dirs[idx])
			raise Rb2RsyncError, "Latest is not a directory: #{latest}" unless latest.nil? || File.directory?(latest)
		end
		latest
	end

	def setup(client)
		Rb2Rsync.info("Setup client #{client}", {:sep=>true})

		@@log.debug "client="+client.inspect
		@@log.debug "client_config="+@rb2conf_clients.inspect
		# rubac.20170221.pidora
		@client=client.to_s
		@bdir=File.join(@dest, @client)
		FileUtils.mkdir_p(@bdir)
		@bdest=File.join(@bdir, @dirstamp)

		@dirs=list_bdest(@bdir)
		@latest = find_latest(@dirs)

		Rb2Rsync.info "latest=#{@latest}"
		Rb2Rsync.info FileUtils.mkdir_p(@bdest, {:noop=>false, :verbose=>true})

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
		cmd =  "rsync -r #{@sshopts} " # #{@sshopts["#{host}"]}"
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

	DEF_OUT_OPTS={:sep=>false, :echo=>false}
	def self.info(msgs, opts=DEF_OUT_OPTS)
		opts=DEF_OUT_OPTS.merge(opts)
		msgs = msgs.join("\n") if msgs.class == Array
		msgs.chomp
		msgs.split(/\n/).each { |msg|
			@@log.info msg unless @@log.nil?
			unless @@maillog.nil?
				opts[:sep] ? @@maillog.separator(msg) : @@maillog.info(msg)
			end
			puts msg if opts[:echo]
		}
	end

	def self.error(msgs, opts={:sep=>false, :echo=>false})
		msgs = msgs.join("\n") if msgs.class == Array
		msgs.chomp
		msgs.split(/\n/).each { |msg|
			@@log.error msg unless @@log.nil?
			@@maillog.error msg unless @@maillog.nil?
			puts msg if opts[:echo]
		}
	end

	def link_latest
		base=File.dirname(@bdest)
		FileUtils.chdir(base) {
			FileUtils.rm_f "latest" if File.symlink?("latest")
			FileUtils.ln_s @bdest, "latest"
		}
	end

	def go(opts)
		#puts @client_config.inspect
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
		cmd = get_cmd(opts)
		@@log.info "cmd=[%s]" % get_cmd(opts)
		opts[:strip]=true
		opts[:lines]=nil
		opts[:out]=@verbose ? $stdout : nil
		opts[:log]=@@log
		opts[:filter]=@verbose ? nil : /\sis\suptodate$/

		Rb2Rsync.info "Running #{cmd}"
		exit_status = Runner::run3!(cmd, opts)
		case exit_status
		when 23,24
			Rb2Rsync.info "Rb2Rsync command success exit_status = #{exit_status}: [#{cmd}]"
			link_latest
		when 0
			Rb2Rsync.info "Rb2Rsync command success: [#{cmd}]"
			link_latest
		else
			Rb2Rsync.error "Rb2Rsync failed, exit_status == #{exit_status}"
			if @action == :run
				es=Runner::run3!("rm -rvf #{@bdest}/", opts)
				Rb2Rsync.error "Failed to remove failed backup in #{@bdest}" unless es == 0
			end
		end
		FileUtils.rmdir(@bdest, {:verbose=>true})
		exit_status
	end

	def test_clients(clients)
		if clients.empty?
			c=@rb2conf_clients.keys
			error c.empty? ? "No clients configured" : "No clients specified, use --all to #{@action.to_s} backup #{@rb2conf.clients.keys.inspect}"
		else
			failed = false
			#ssh -q -o "BatchMode=yes" -i ~/.ssh/id_rsa "$c" exit
			clients.each { |client|
				Rb2Rsync.info("Testing client #{client}", {:sep=>true})
				c=client.to_s
				puts @rb2conf_clients.inspect
				cc=@rb2conf_clients[client.to_sym]
				a=cc.get_ssh_address
				next if a.nil?
				cmd = %Q[ssh -q -o "BatchMode=yes" -i ~/.ssh/id_rsa "#{a}" exit]
				es = Runner::run3!(cmd, {:strip=>true, :out=>$stdout, :log=>@@log})
				if es != 0
					Rb2Rsync.error "Failed to ssh to client #{c} with address #{a}"
					failed = true
				end
			}
			clients.clear if failed
		end
		clients
	end

	def df_h
		Rb2Rsync.info("$ df -h #{@bdest}\n#{%x/df -h #{@bdest}/}", {:echo=>true})
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
			test_clients(clients).each { |client|
				@@maillog.separator(client.to_s)
				next unless setup(client)
				go(opts)
			}
			df_h
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
			test_clients(clients).each { |client|
				@@maillog.separator(client.to_s)
				next unless setup(client)
				go(opts)
			}
			df_h
		}
		mopts = {
			:subject => "Update backup finished: #{clients.join(',')}",
			:email_from => @email,
			:email_to   => @email
		}
		@@maillog.mail(mopts)
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
