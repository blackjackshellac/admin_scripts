#!/usr/bin/env ruby
#
# Watch for changes to the home directory looking for print to file jobs from firefox
# to the file ~/mozilla.pdf and prompt the user for a more appropriate name
#

begin
	require 'rb-inotify'
rescue LoadError => e
	puts "ERROR: #{e} - run\n\tgem install rb-inotify"
	exit 1
end
require 'fileutils'
require 'logger'
require 'optparse'
require 'etc'
require 'tk'

class Logger
	DATE_FORMAT="%Y-%m-%d %H:%M:%S"

	##
	# Send an error message
	#
	# @param [String] msg error message
	#
	def err(msg)
		error(msg)
	end

	##
	# Print an error message and exit immediately with exit errno 1
	#
	# @param [String] msg error message
	# @param [Integer] errno optional exit errno value, default is 1
	#
	def die(msg, errno=1)
		error(msg)
		exit errno
	end

	##
	# Create a logger with the given stream or file
	#
	# @overload create(filename, level)
	#   Create a file logger
	#   @param [String] stream filename
	#   @param [Integer] level log level
	# @overload create(iostream, level)
	#   @param [IO] stream STDOUT or STDERR or other io stream
	#   @param [Integer] level log level
	#
	# @return [Logger] the logger object
	#
	def self.create(stream, level=Logger::INFO)
		log = Logger.new(stream)
		log.level = level
		log.datetime_format = DATE_FORMAT
		log.formatter = proc do |severity, datetime, progname, msg|
			"#{severity} #{datetime}: #{msg}\n"
		end
		log
	end

end

$log = Logger.create(STDERR)

class InotifyEvent

		attr_reader :event
		##
		# Create a new instance of an InotifyEvent
		#
		# @param [INotify::Event] event event to set to instance
		#
		def initialize(event)
			@event = event
		end

		##
		# summarize current event when debugging
		#
		def summarize
			return unless $log.level == Logger::DEBUG
			$log.debug "-"*80
			$log.debug "absolute_name>>"+@event.absolute_name
			$log.debug "name>>"+@event.name
			$log.debug "flags>>"+@event.flags.inspect
			$log.debug "notifier>>"+@event.notifier.inspect
			$log.debug "event.watcher.flags>>"+@event.watcher.flags.inspect

			$log.debug "event=["+@event.inspect+"]"
		end

		##
		# Check that a flag is set for this event
		#
		# @param [Integer] flag event flag to test
		#
		def has_flag(flag)
			@event.flags.include?(flag)
		end

		##
		# Check that the event is for the given file path
		#
		# @param [String] absolute_name path to check against event
		#
		def has_absolute_name(absolute_name)
			absolute_name.eql?(@event.absolute_name)
		end

		##
		# Get absolute name of path from event
		#
		# @return [String] absolute path name of event
		#
		def absolute_name
			@event.absolute_name
		end

		##
		# Return array of matched flag(s)
		#
		# @return [Array] flags matched by event
		#
		def flags
			@event.flags
		end
end

class ShellUtil
	# Cross-platform way of finding an executable in the $PATH.
	#
	# @example ShellUtil.which('ruby') #=> /usr/bin/ruby
	def self.which(cmd)
	  exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
	  ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
	    exts.each do |ext|
	      exe = File.join(path, "#{cmd}#{ext}")
	      return exe if File.executable?(exe) && !File.directory?(exe)
	    end
	  end
	  nil
	end

	#
	# if the destination file exists, rename it with its last modification time
	#
	# @example mozilla.pdf -> mozilla_20201030_152222.pdf
	#
	# @param [String] dest destination file name
	#
	def self.backupDestinationFile(dest)
		return unless File.exist?(dest)

		ddir=File.dirname(dest)
		fext=File.extname(dest)
		fbase=File.basename(dest, fext)

		begin
			fstat=File.lstat(dest)
		rescue => e
			raise "Failed to stat destination file: #{dest} [#{e.to_s}]"
		end

		Dir.chdir(ddir) {
			$log.debug "%s = [%s]" % [ dest, fstat.inspect ]

			mtime=fstat.mtime
			bdest=mtime.strftime("#{fbase}_%Y%m%d_%H%M%S#{fext}")
			$log.info "Backup #{dest} to #{bdest}"
			e = FileUtils.mv(dest, bdest)
			$log.error "Failed to backup #{dest}: #{e}" unless e == true
		}
	end

	##
	# File stat for the given path
	#
	# @param [String] path for stat
	#
	# @return [File::Stat] stat data object
	# @return [NilClass] path not found
	#
	def self.lstat(path)
		File.lstat(path)
	rescue
		nil
	end

	##
	# Return the user id of the specified user
	#
	# @param [String] user username
	#
	# @return [Integer] uid of the given user
	# @return [Null] if user not found
	def self.get_useruid(user)
		Etc.getpwnam(user).uid.to_i
	rescue
		nil
	end

	##
	# Find the proc directory for the given process name and user
	#
	# @param [String] process_name process name
	# @param [String] user user name
	#
	# @return [Array] array of process ids matching process name and user
	#
	def self.proc_cmdline(process_name, user=nil, oneshot=false)
		uid = get_useruid(user)
		pids=Dir.glob("/proc/[0-9]*")
		$log.debug "Searching for #{process_name} for #{user} #{uid}"

		regexp=/#{Regexp.quote(process_name)}$/
		ipids=[]

		pids.each { |pid|
			unless uid.nil?
				dstat=lstat(pid)
				next if dstat.nil? || dstat.uid != uid
			end
			pid_cmdline=File.join(pid, "cmdline")
			cmdline=File.read(pid_cmdline).strip
			# cmdline and options are split by EOS character
			chunks=cmdline.split(/\0/)
			chunks.each { |chunk|
				next if chunk[regexp].nil?
				ipid = File.basename(pid).to_i
				if ipid == Process.pid
					$log.debug "Don't kill yourself, ignoring pid=#{ipid}"
					next
				end
				$log.debug "#{uid}.#{pid}>> [#{process_name} in #{chunks.inspect}]"
				ipids << ipid
				return ipids if oneshot
			}
		}
		ipids
	end

	##
	# Return the current username
	#
	# @return [String] user name of the current user
	#
	def self.getUser
		return Etc.getlogin
	end

	# Get the process id for the given process and user
	#
	# @param [String] process_name process name
	# @param [String] user current user if not specified
	#
	# @return [String] pid of given process or empty string if not found
	#
	def self.pidOf(process_name, user=nil)
		user=getUser if user.nil?
		pids=proc_cmdline(process_name, user, true)
		pids.empty? ? "" : pids[0].to_s
	end

	##
	# Kill the given pid
	#
	# @param [Integer] pid to kill
	# @param [String] signal if given, TERM by default
	#
	# @return [TrueClass] on success
	# @return [FalseClass] on failure
	#
	def self.killProcessByPid(pid, signal="TERM")
		$log.info "Killing pid=#{pid} signal=#{signal}"
		Process.kill(signal, pid.to_i)
		true
	rescue => e
		$log.error "Failed to kill process with pid=#{pid}: #{e}"
		false
	end

	##
	# Kill the process with the given process Name
	#
	# @param [String] process_name process name
	#
	def self.killProcessByName(process_name)
		$log.debug "Killing #{process_name}"
		pid=ShellUtil.pidOf(process_name)
		return if pid.empty?
		$log.debug "Process pid=#{pid}"
		killProcessByPid(pid.to_i)
	end

		##
	# Move file from soure to Destination
	#
	# @param src [String] source file path
	# @param dst [String] destination file path
	#
	# @return [TrueClass] on success
	# @return [Exception] on failure
	def self.mv(src,dst)
		begin
			FileUtils.mv(src, dst)
		rescue => e
			return e
		end
		true
	end

	##
	# Delete the given file
	#
	# @param [String] file file to delete
	#
	# @return [TrueClass] on success
	# @return [Exception] on failure
	def self.rm_f(file)
		begin
			FileUtils.rm_f(file)
		rescue => e
			return e
		end
		true
	end

	##
	# Creates a directory and all its parent directories.
	#
	# @param [String] dir directory path to create
	#
	# @return [TrueClass] on success
	# @return [FalseClass] on failure
	#
	def self.mkdir_p(dir)
		FileUtils.mkdir_p(dir)
		true
	rescue => e
		false
	end

	##
	# default options for ShellUtil.find()
	#
	FIND_OPTS={
		:recurse=>false,
		:max_mtime=>Time.now,
		:min_mtime=>Time.at(0)
	}

	##
	# search the given directory for files that match the given filespec
	# @param [String] dir directory path to find in
	# @param [String] fspec file glob
	# @param [Hash] opts find options
	# @option opts [Boolean] :recurse
	# @option opts [Time] :max_mtime maximum time, defaults to Time.now
	# @option opts [Time] :min_mtime minimum time, defaults to Time.at(0)
	#
	# @yield [String,File::Stat] file path and its stat structure
	def self.find(dir, fspec, opts=FIND_OPTS)
		opts=FIND_OPTS.merge(opts)
		dir=File.expand_path(dir)
		Dir.chdir(dir) {
			glob=opts[:recurse] ? File.join("**", fspec) : fspec
			Dir.glob(glob) { |file|
				fstat = File.lstat file
				if fstat.directory?
					puts "dir=#{dir} file=#{file}"
					find(File.join(dir, file), fspec, opts)
					next
				end
				next if fstat.mtime >= opts[:max_mtime]
				next if fstat.mtime <= opts[:min_mtime]
				yield File.join(dir, file), fstat
			}
		}
	end
end

class FirefoxPrint2FileWatcher
	## Process name with extension
	MERB=File.basename($0)
	## Process name without .rb extension
	ME=File.basename($0, ".rb")
	# Directory where the script lives, resolves symlinks
	MD=File.expand_path(File.dirname(File.realpath($0)))

	DEFAULTS={
		:force=>false,
		:watchpath=>File.expand_path("~/mozilla.pdf"),
		:destdir=>ENV['FFP2FW_DESTDIR']||"/var/tmp/mozilla",
		:run=>false,
		:kill=>false,
		:autostart=>false,
		:logfile=>false,
		:clean => false,
		:clean_opts => {
			:timespec=>"8w",
			:recurse=>true,
			:max_mtime=>Time.at(Time.now.to_i-4*24*3600),
			:min_mtime=>Time.at(0)
		}
	}

	attr_reader :force, :watchpath, :destdir, :run, :kill, :autostart, :clean, :clean_opts, :log, :logfile
	attr_reader :watchext, :watchbase, :watchdir, :watchfile
	def initialize
		DEFAULTS.each_pair { |key,val|
			instance_variable_set("@#{key}", val)
		}
		@watchext=File.extname(@watchpath)
		@watchbase=File.basename(@watchpath, @watchext)
		@watchdir=File.dirname(@watchpath)
		@watchfile=File.basename(@watchpath)

		@log=File.join(@destdir, ME+".log")
	end

	def parse_clargs()
		optparser=OptionParser.new { |opts|
			opts.banner = "#{MERB} [options]\n"

			opts.on('-d', '--dir ', String, "Directory for pdf output files, default #{@destdir}") { |dir|
				@destdir = dir
			}

			opts.on('-f', '--[no-]force', "Remove existing watch file on startup, default #{@force}") { |bool|
				@force = bool
			}

			opts.on('-r', '--run', "Run the inotify watcher") {
				@run = true
			}

			opts.on('-k', '--kill', "Kill the running process, if any") {
				@kill = true
			}

			# nn[smhdw] mod is seconds|minutes|hours|days|weeks
			opts.on('-c', '--clean [TIMESPEC]', String, "Cleanup files older than NNN[smhdwy], eg 30d for 30days, default=#{@clean_opts[:timespec]}") { |timespec|
				@clean_opts[:timespec] = timespec unless timespec.nil?
				@clean_opts[:max_mtime] = FirefoxPrint2FileWatcher.	parse_timespec(@clean_opts[:timespec])
				@clean = true
			}

			opts.on('-l', '--log [LOGPATH]', String, "Log to file instead of console, default #{@log}") { |log|
				@log = File.expand_path(log) unless log.nil?
				@logfile = true
			}

			opts.on('-a', '--autostart', "Add desktop file to ~/.config/autostart and ~/.local/share/applications") {
				@autostart = true
			}

			opts.on('-D', '--debug', "Enable debugging output") {
				$log.level = Logger::DEBUG
			}

			opts.on('-h', '--help', "Help") {
				$stdout.puts ""
				$stdout.puts opts
				exit 0
			}
		}
		optparser.parse!

		$log.die "Failed to create destination directory: #{@destdir}" unless ShellUtil.mkdir_p(@destdir)

	end

	##
	# Create a timespec string with appropriate plural
	#
	# @example 5, :second -> "5 seconds"
	#
	# @param [Integer] val integer value
	# @param [Symbol] mod timespec modifier
	#
	# @return [String] timespec string
	#
	def self.timespec_as_text(val, mod)
		suffix= val == 1 ? "" : "s"
		"#{mod}#{suffix}"
	end

	TIMESPEC_MODIFER_LOOKUP = {
		:s => { :text=>:second, :mult=>1 },
		:m => { :text=>:minute, :mult=>60 },
		:h => { :text=>:hour,   :mult=>3600 },
		:d => { :text=>:day,		:mult=>86400 },
		:w => { :text=>:week,	:mult=>604800 }
	}
	##
	# parse a timespec of the form NN[smhdw] where the modifiers represent seconds,
	# minutes, hours, days or weeks
	#
	# @example timespec=86400s or 86400 both represent 24 hours
	#
	# @param [String] timespec timespec of the form NN[smhdw]
	#
	# @return [Time] time object seconds before now
	#
	def self.parse_timespec(timespec)
		m=/(?<val>\d+)(?<mod>[smhdw]?)/.match(timespec)
		raise "No regex match" if m.nil?
		timespec_mod=m[:mod].empty? ? :unknown : m[:mod].to_sym
		timespec_val=m[:val].to_i
		lookup = TIMESPEC_MODIFER_LOOKUP[timespec_mod]
		raise "Unknown timespec modifier: #{timespec_mod}" if lookup.nil?
		secs = timespec_val*lookup[:mult]
		mod = timespec_as_text(timespec_val, lookup[:text])
		ptime=Time.at(Time.now.to_i-secs)
		$log.info "#{timespec}> delete files older than #{timespec_val} #{mod} ago = #{ptime}"
		ptime
	rescue => e
		$log.die "Failed to parse time spec: #{timespec} - #{e}"
	end

	##
	# Search destdir for *.pdf files and delete those older than @clean_opts
	#
	def cleanup
		return unless @clean

		ShellUtil.find(@destdir, "*.pdf", @clean_opts) { |file,fstat|
			if @force
				$log.info "Deleting #{file}: #{fstat.mtime}"
				ShellUtil.rm_f(file)
			else
				$log.info "Use -f to delete #{file}: #{fstat.mtime}"
			end
		}
	end

	##
	# Create an autostart desktop file, and place a desktop file in
	# ~/.config/autostart/
	# ~/.local/share/applications/
	#
	def createAutostart
		return unless @autostart

		# -k - kill existing process owned by user
		# -f - force operations (clean, kill, etc)
		# -c - clean files from destdir older than 8 weeks
		# -r - run the inotify watcher
		# -l - log to file
		def_options="-k -f -c -r -l"
		desktop_entry=%Q([Desktop Entry]
Name=#{ME}
GenericName=#{ME}
Comment=Watch mozilla.pdf file for changes
Exec=#{File.join(MD, MERB)} #{def_options}
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
)
		desktop_file=ME+".desktop"
		autostart_desktop=File.join(ENV['HOME'], ".config/autostart/#{desktop_file}")
		$log.info "Writing autostart #{autostart_desktop}"
		File.open(autostart_desktop, "w") { |fd|
			fd.puts desktop_entry
		}
		local_app_desktop=File.join(ENV['HOME'], ".local/share/applications/#{desktop_file}")
		$log.info "Writing "+local_app_desktop
		File.open(local_app_desktop, "w") { |fd|
			fd.puts desktop_entry
		}
		puts desktop_entry
	rescue => e
		$log.die "createAutostart failed: #{e}"
	end

	##
	# search for another running instance of the MERB process by name
	# and kill it
	#
	def killRunning
		$log.info "Killing #{MERB}"
		ShellUtil.killProcessByName(MERB)
	end

	##
	# @return [Boolean] true if already running, false otherwise
	def isRunning
		ShellUtil.pidOf(MERB).empty? ? false : true
	end

	def checkWatchPath
		return unless File.exist?(@watchpath)
		raise "Watch file #{@watchpath} exists - will not delete without force option" unless @force
		ShellUtil.rm_f(@watchpath)
	rescue => e
		$log.die e.to_s
	end

	TK_DIALOG_TITLE="Firefox print to file"
	def runNotifyWatch
		notifier = nil
		begin
			notifier = INotify::Notifier.new

			$log.info "Watching #{@watchdir} for updates to #{@watchfile}"
			notifier.watch(@watchdir, :moved_to, :create) { |event|
				iev = InotifyEvent.new(event)

				iev.summarize

				if iev.has_absolute_name(@watchpath) && (iev.has_flag(:moved_to) || iev.has_flag(:create))
					$log.info "Found watch file: #{@watchpath} - #{iev.flags.inspect}"

					dest=@destdir
					$log.info "Tk.getSaveFile in #{@destdir}"
					file=Tk.getSaveFile(
						:initialdir=>@destdir,
						:initialfile=>@watchfile,
						:title=>TK_DIALOG_TITLE,
						:confirmoverwrite=>false,
						:defaultextension=>'.pdf',
						:filetypes=>[
							['PDF Files', '.pdf'],
							['ALL Files', '*']
						]
					)
					if file.empty?
						file=@watchfile
						dest=File.join(@destdir, file)
						msg="Destination file defaulting to #{dest}"
						$log.warning msg
						Tk::messageBox(
							:type => "ok",
							:message => msg,
							:icon => "warning",
							:title => TK_DIALOG_TITLE
						)
					else
						# add an extension if necessary
						file+=@watchext if File.extname(file).empty?
						dest = file
					end

					#
					# if the destination exists, rename it with its create time
					#
					$log.info "Destination file is #{dest}"

					ShellUtil.backupDestinationFile(dest)

					res = ShellUtil.mv(iev.absolute_name, dest)
					if res == true
						$log.info "Renamed file #{iev.absolute_name} to #{dest}"
						%x(nautilus #{@destdir} &)
					else
						msg="Failed to move #{iev.absolute_name} to #{dest}"
						$log.error "#{msg}: #{res.to_s}"
						Tk::messageBox(
							:type => "ok",
							:message => msg,
							:icon => "error",
							:title => TK_DIALOG_TITLE
						)
					end

				else
					$log.debug "Ignoring file: #{iev.absolute_name} with flags=#{iev.flags.inspect}"
				end
			}

			$log.debug "Watching for updates to #{@watchpath}"
			$log.debug "Running notifier: #{notifier.inspect}"
			notifier.run
		rescue Interrupt => e
			$log.info "Shutting down"
			exit 0
		rescue => e
			$log.error e.to_s
			puts e.to_s
			exit 1
		ensure
			notifier.stop unless notifier.nil?
		end
	end
end

ffp2fw = FirefoxPrint2FileWatcher.new
begin
	ffp2fw.parse_clargs

	ffp2fw.createAutostart if ffp2fw.autostart
	ffp2fw.checkWatchPath unless ffp2fw.force

	if ffp2fw.logfile
		$log.info "Logging to file #{ffp2fw.log}"
		$log = Logger.create(ffp2fw.log, $log.level)
	end

	ffp2fw.killRunning if ffp2fw.kill
	ffp2fw.cleanup if ffp2fw.clean

	unless ffp2fw.run
		$log.debug "Not running inotify watcher"
		exit 0
	end

	raise RuntimeError, "The script is already running, use -k to reload" if ffp2fw.kill == false && ffp2fw.isRunning

	$log.info "Running in foreground #{Process.pid}"
	ffp2fw.runNotifyWatch
rescue RuntimeError => e
	$log.warn e.message
rescue => e
	$log.error "#{e.class}Caught exception: #{e.message}"
	puts e.backtrace.join("\n")
end

exit 1
