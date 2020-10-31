#!/usr/bin/env ruby
#
# Watch for changes to the home directory looking for print to file jobs from firefox
# to the file ~/mozilla.pdf and prompt the user for a more appropriate name
#

# gem install rb-inotify
begin
	require 'rb-inotify'
rescue LoadError => e
	puts "ERROR: #{e} - run\n\tgem install rb-inotify"
	exit 1
end
require 'fileutils'
require 'logger'
require 'optparse'
require 'daemons'

MERB=File.basename($0)
ME=File.basename($0, ".rb")
MD=File.expand_path(File.dirname(File.realpath($0)))

class Logger
	def err(msg)
		self.error(msg)
	end

	def die(msg)
		self.error(msg)
		exit 1
	end

	def self.set_logger(stream, level=Logger::INFO)
		log = Logger.new(stream)
		log.level = level
		log.datetime_format = "%Y-%m-%d %H:%M:%S"
		log.formatter = proc do |severity, datetime, progname, msg|
			"#{severity} #{datetime}: #{msg}\n"
		end
		log
	end

end

$log = Logger.set_logger(STDERR)

$opts={
	:force=>false,
	:watchpath=>File.expand_path("~/mozilla.pdf"),
	:destdir=>"/var/tmp/mozilla",
	:bg=>false,
	:kill=>false,
	:autostart=>false
}

$opts[:log]=File.join($opts[:destdir], ME+".log")

optparser=OptionParser.new { |opts|
	opts.banner = "#{MERB} [options]\n"

	opts.on('-d', '--dir ', String, "Directory for pdf output files, default #{$opts[:destdir]}") { |dir|
		$opts[:destdir]=dir
	}

	opts.on('-f', '--[no-]force', "Remove existing watch file on startup, default #{$opts[:force]}") { |bool|
		$opts[:force]=bool
	}

	opts.on('-b', '--bg', "Run as a background daemon") {
		$opts[:bg]=true
	}

	opts.on('-k', '--kill', "Kill the running process, if any") {
		$opts[:kill]=true
	}

	opts.on('-a', '--autostart', "Add desktop file to ~/.config/autostart and ~/.local/share/applications") {
		$opts[:autostart]=true
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

FileUtils.mkdir_p($opts[:destdir])

$opts[:watchext]=File.extname($opts[:watchpath])
$opts[:watchbase]=File.basename($opts[:watchpath], $opts[:watchext])
$opts[:watchdir]=File.dirname($opts[:watchpath])
$opts[:watchfile]=File.basename($opts[:watchpath])

class InotifyEvent

		attr_reader :event
		def initialize(event)
			@event = event
		end

		def summarize
			return unless $log.level == Logger::DEBUG
			$log.debug "-"*80
			$log.debug "absolute_name>>"+@event.absolute_name
			$log.debug "name>>"+@event.name
			$log.debug "flags>>"+@event.flags.inspect
			$log.debug "notifier>>"+@event.notifier.inspect
			$log.debug "event.watcher.flags>>"+@event.watcher.flags.inspect
		end

		def has_flag(flag)
			return @event.flags.include?(flag)
		end

		def has_absolute_name(absolute_name)
			return absolute_name.eql?(@event.absolute_name)
		end

		def absolute_name
			@event.absolute_name
		end

		def flags
			@event.flags
		end
end

# Cross-platform way of finding an executable in the $PATH.
#
#   which('ruby') #=> /usr/bin/ruby
def which(cmd)
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
# if the destination exists, rename it with its create time
#
def backupDestinationFile(dest)
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
		FileUtils.mv(dest, bdest)
	}
end

def pidOf(process_name)
	%x/pidof #{process_name}/.strip
end

if File.exist?($opts[:watchpath])
	$log.die "Watch file #{$opts[:watchpath]} exists - will not delete without force option" unless $opts[:force]
	FileUtils.rm($opts[:watchpath])
end

if $opts[:autostart]
	desktop_entry=%Q(
[Desktop Entry]
Name=firefox_print2file_watcher
GenericName=firefox_print2file_watcher
Comment=Watch mozilla.pdf file for changes
Exec=#{File.join(MD, MERB)} -b -f -k
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

	exit 0
end

if $opts[:kill]
	pid=pidOf(MERB)
	unless pid.empty?
		$log.info "Killing pid=#{pid}"
		out=%x/kill #{pid}/
		if $?.exitstatus != 0
			puts out
			$log.die "Failed to kill process with pid=#{pid}"
		end
	end
	exit 0 unless $opts[:bg]
end

$zenity = which('zenity')
$log.die "zenity not found" if $zenity.nil?

if $opts[:bg]
	pid=pidOf(MERB)
	$log.die "Already running with pid=#{pid}" unless pid.empty?
	$log.info "Running in background, logging to #{$opts[:log]}"
	Daemons.daemonize({:app_name=>MERB})
	$log = Logger.set_logger($opts[:log], $log.level)
	$log.info "Background process pid #{Process.pid}"
end

notifier = nil
begin

	notifier = INotify::Notifier.new

	notifier.watch($opts[:watchdir], :moved_to, :create) { |event|
		iev = InotifyEvent.new(event)

		iev.summarize
		$log.debug "\n"+iev.event.inspect

		if iev.has_absolute_name($opts[:watchpath]) && (iev.has_flag(:moved_to) || iev.has_flag(:create))
			$log.info "Found watch file: #{$opts[:watchpath]} - #{iev.flags.inspect}"

			file=%x/#{$zenity} --entry --text="Enter the print to file name" --entry-text="#{$opts[:watchbase]}" --title="Firefox print to file"/.chomp
			if $?.exitstatus == 0 && !file.empty?
				# add an extension if necessary
				file+=$opts[:watchext] if File.extname(file).empty?
			else
				file=$opts[:watchfile]
				warning="Destination file set to #{file}"
				%x/#{$zenity} --warning --text="#{warning}" --title="Firefox print to file" --no-wrap/
				$log.warn warning
			end

			#
			# if the destination exists, rename it with its create time
			#
			dest=File.join($opts[:destdir], file)
			$log.info "Destination file is #{dest}"

			backupDestinationFile(dest)

			FileUtils.mv(iev.absolute_name, dest)
			#%x(zenity --no-wrap --info --text="<b>Renamed file to</b> <tt>#{dest}</tt> --title="Firefox print to file")
			$log.info "Renamed file #{iev.absolute_name} to #{dest}"
			%x(nautilus #{$opts[:destdir]} &)

		else
			$log.debug "Ignoring file: #{iev.absolute_name} with flags=#{iev.flags.inspect}"
		end
	}

	$log.info "Watching for updates to #{$opts[:watchpath]}"
	$log.debug "Running notifier: #{notifier.inspect}"
	notifier.run
rescue Interrupt => e
	$log.info "\nShutting down"
	exit 0
rescue => e
	$log.error e.to_s
	puts e.to_s
ensure
	notifier.stop unless notifier.nil?
end

exit 1
