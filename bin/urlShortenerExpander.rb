#!/usr/bin/env ruby
#
#
# $ curl --head https://bit.ly/2VG243x
# HTTP/2 301
# server: nginx
# date: Sat, 05 Dec 2020 12:36:22 GMT
# content-type: text/html; charset=utf-8
# content-length: 116
# cache-control: private, max-age=90
# content-security-policy: referrer always;
# location: https://t.co/8wSEtFwd0r?amp=1
# referrer-policy: unsafe-url
# via: 1.1 google
# alt-svc: clear

require 'optparse'
require_relative './lib/logger'

url='https://bit.ly/2VG243x'

class UrlShortenerExpander
	LOCATION_REGEX=/^location:\s*(?<location>.*)$/i
	## Process name with extension
	MERB=File.basename($0)
	## Process name without .rb extension
	ME=File.basename($0, ".rb")
	# Directory where the script lives, resolves symlinks
	MD=File.expand_path(File.dirname(File.realpath($0)))

	LAUNCH_BROWSER = ENV['URL_EXPANDER_BROWSER']||'firefox'

	attr_reader :results, :source, :chain, :dest, :stime, :dtime, :url, :launch
	def initialize(url)
		@url = url
		@logger=Logger.create(STDERR)
		@url=""
		@chain=[]
		@dest=nil
		@stime=Time.now
		@dtime=0
		@launch = nil
	end

	def parse_clargs
		optparser=OptionParser.new { |opts|
			opts.banner = "#{MERB} [options]\n"

			opts.on('-u', '--url URL', String, "Shortened url to expand") { |url|
				set_source(url)
			}

			opts.on('-l', '--launch [BROWSER]', String, "Launch desintation in browser, def is #{LAUNCH_BROWSER}") {|browser|
				@launch = browser.nil? ? LAUNCH_BROWSER : browser
			}

			opts.on('-D', '--debug', "Enable debugging output") {
				@logger.level = Logger::DEBUG
			}

			opts.on('-h', '--help', "Help") {
				$stdout.puts ""
				$stdout.puts opts
				$stdout.puts <<~HELP

					Environment Variables

					URL_EXPANDER_BROWSER - set the browser to launch the desination url

				HELP
				exit 0
			}
		}
		optparser.parse!

		if @url.empty?
			set_source(ARGV[0]) if ARGV.length > 0
			@logger.die "Must specify a url with -u #{ARGV[0]}" if @url.empty?
		end
	end

	def chain_to_s(indent)
		str=""
		@chain.each_with_index { |url, idx|
			str+="%s[%d] %s\n" % [ indent, idx+1, url ]
		}
		str
	end

	def set_source(url)
		@url=url
		@chain=[ url ]
		@stime=Time.now
	end

	def expand(url=nil)

		url=@url if url.nil?

		stime=Time.now
		@logger.info "Fetching headers #{url}"
		headers=%x(curl --silent --head '#{url}')
		dsecs=Time.now.to_f-stime.to_f
		@logger.debug "Fetched #{url} in #{dsecs} seconds"
		#puts "\nheaders=#{headers}"

		location=""
		headers.split(/\n/).each { |line|
			#puts line
			m = LOCATION_REGEX.match(line)
			unless m.nil?
				location=m[:location].strip
				#puts "#{url} -> #{location}"
				@chain << location
			 	expand(location)
				return
			end
		}
		# location: header not found, url is the destination
		@dtime=Time.now.to_f-@stime.to_f
		@dest=url


		%x/#{@launch} "#{@dest}"/ unless @launch.nil?

		return
	end

	def format(fmt, label, value=nil)
		fmt % [ label, value ]
	end

	def summarize(stream=STDOUT)
		# <<~ strips off leading whitespace before the heredoc
		<<~SUMMARY

		#{format("%12s: %s", "Url", @url )}
		#{format("%12s: %s", "Destination", @dest)}
		#{format("%12s: %.3f", "RunTime", @dtime)} seconds

		#{format("%12s:", "Chain")}
		#{chain_to_s(" "*14)}
		SUMMARY
	end
end


use=UrlShortenerExpander.new(url)
use.parse_clargs
use.expand()
puts use.summarize
