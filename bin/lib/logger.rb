require 'logger'

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
