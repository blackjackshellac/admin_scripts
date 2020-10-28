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
	:watch=>File.expand_path("~/mozilla.pdf"),
	:destdir=>"/var/tmp/mozilla",
	:bg=>false
}

$opts[:log]=File.join($opts[:destdir], ME+".log")

optparser=OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]\n"

	opts.on('-d', '--dir ', String, "Directory for pdf output files, default #{$opts[:destdir]}") { |dir|
		$opts[:destdir]=dir
	}

	opts.on('-f', '--[no-]force', "Remove existing watch file on startup, default #{$opts[:force]}") { |bool|
		$opts[:force]=bool
	}

	opts.on('-b', '--bg', "Run as a background daemon") {
		$opts[:bg]=true
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

$opts[:ext]=File.extname($opts[:watch])
$opts[:watchfile]=File.basename($opts[:watch], $opts[:ext])
$opts[:watchdir]=File.dirname($opts[:watch])

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
		FileUtils.mv(dest, bdest)
	}
end

if $opts[:bg]
	pid=%x/pidof #{ME}/.strip
	$log.die "Already running with pid=#{pid}" unless pid.empty?
	$log.info "Running in background"
	Daemons.daemonize({:app_name=>ME})
	$log = Logger.set_logger($opts[:log], $log.level)
	$log.info "Background rocess pid=#{Process.pid}"
end

notifier = nil
begin
	$zenity = which('zenity')
	raise "zenity not found" if $zenity.nil?

	if File.exist?($opts[:watch])
		raise "Watch file exists will not delete without force option" unless $opts[:force]
		FileUtils.rm($opts[:watch])
	end

	notifier = INotify::Notifier.new

	notifier.watch($opts[:watchdir], :moved_to) { |event|
		iev = InotifyEvent.new(event)

		iev.summarize
		$log.debug "\n"+iev.event.inspect

		if iev.has_absolute_name($opts[:watch]) && iev.has_flag(:moved_to)
			$log.info "Found watch file: #{$opts[:watch]}"

			file=%x/#{$zenity} --entry --text="Enter the print to file name" --entry-text="#{$opts[:watchfile]}" --title="Firefox print to file"/.chomp
			if file.empty?
				file=Time.now.strftime("#{$opts[:watchfile]}_%Y%m%d_%H%M%S#{$opts[:ext]}")
			else
				# add an extension if necessary
				file+=$opts[:ext] if File.extname(file).empty?
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
			$log.debug "Ignoring file: #{iev.absolute_name}"
		end
	}

	$log.info "Running notifier: #{notifier.inspect}"
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
