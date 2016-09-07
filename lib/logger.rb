#
#
#

require 'logger'

class Logger
	def die(msg)
		$stdout = STDOUT
		self.error(msg)
		exit 1
	end

	def puts(msg)
		self.info(msg)
	end

	def write(msg)
		self.info(msg)
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


