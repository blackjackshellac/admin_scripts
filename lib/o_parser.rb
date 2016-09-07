#
#
#

require 'optparse'

class OParser
	def initialize()
	end

	def self.verbose(gopts)
		gopts[:verbose]=true
		@@log.level = Logger::INFO
	end

	def self.debug(gopts)
		gopts[:debug]=true
		@@log.level = Logger::DEBUG
	end

	def self.help(gopts, opts, help_text)
		$stdout.puts ""
		$stdout.puts opts
		$stdout.puts help_text
		exit 0
	end

	def self.parse(gopts, help_text, &block)
		@@log=gopts[:logger]
		raise "Logger not set in OParser" if @@log.nil?
		if help_text.nil?
			help_text = ""
		elsif File.exists?(help_text)
			help_text=File.read(help_text)
		end
		optparser = OptionParser.new { |opts|
			opts.banner = "#{ME}.rb [options]\n"

			block.call(opts) unless block.nil?

			opts.on('-v', '--verbose', "Verbose output") {
				verbose(gopts)
			}

			opts.on('-D', '--debug', "Turn on debugging output") {
				debug(gopts)
			}

			opts.on('-h', '--help', "Help") {
				help(gopts, opts, help_text)
			}

		}
		optparser.parse!
		gopts
	rescue OptionParser::InvalidOption => e
		@@log.die "Invalid option: "+e.message
	rescue => e
		e.backtrace.each { |tr|
			puts tr
		}
		@@log.die "Exception: "+e.message
	end
end

