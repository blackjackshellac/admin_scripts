#
#
#

require 'netaddr'

class WhoisBayes
	class WhoisRateError < StandardError
	end

	RE_WHOIS_COMMENT=/(.*)(#%.*)$/
	RE_CAT=/([-\w;]*):(.*)/
	RE_NETWORK=/^\s*network:/

	@@log = nil
	@@unknown = nil

	# :cidr => WhoisData
	@@cache = {}

	attr_reader :wbc
	def initialize
		@wbc = ClassifierReborn::Bayes.new(WhoisData.cat_keys)
		@sleep = 1
	end

	def self.init(opts)
		@@log = opts[:logger] if @@log.nil?
		raise "Logger not set in init" if @@log.nil?
		@@unknown = {} if @@unknown.nil?
	end

	def self.loadTraining(file)
		wb = WhoisBayes.new
		wb.load(File.read(file)) 
		wb
	end

	def self.unknown
		@@unknown
	end

	def saveTraining(file)
		@@log.info "Writing whois training data: #{file}"
		data = Marshal.dump @wbc
		File.open(file, "w") { |fd|
			fd.write(data)
		}
	end

	def load(data)
		@wbc = Marshal.load data
	end

	def categorize_line(line)
		unless line[RE_WHOIS_COMMENT].nil?
			line = $1.strip
			comment = $2.strip
			@wbc.train(:ignore, comment)
			@@log.debug "Stripped comment: #{comment}"
		end
		line.strip!
		return if line.empty?

		# TODO fix hackish tweak to deal with network: prefix
		line.sub!(RE_NETWORK, "") unless line[RE_NETWORK].nil?

		# extract category from line
		if line[RE_CAT].nil?
			@@log.debug "ignore category not found in input: '#{line}'"
			@wbc.train(:ignore, line)
			return
		end
		cat=$1.strip.downcase
		val=$2.strip

		return if @@unknown.keys.include?(cat)

		if WhoisData.is_ignore(cat)
			@@log.debug "classify ignore #{cat}: #{line}"
			@wbc.train(:ignore, line)
			return	
		end
		kat = WhoisData.get_category(cat)
		if kat.nil?
			@@unknown[cat] = line
			@@log.warn "#{cat} category not found in input: #{line}"
		else
			@@log.info "classify #{cat} as #{kat}: #{line}"
			@wbc.train(kat, line)
		end
	end

	def categorize(addr)
		@@log.debug "categorize>>> whois #{addr}"
		WhoisData.whois(addr).each { |line|
			categorize_line(line)
		}
	end

	def cache_put(wd)
		return if wd.cidr.nil?
		wd.cidr.each { |cidr|
			cidr_s = cidr.to_s
			@@cache[cidr_s] = wd unless @@cache.key?(cidr_s)
		}
	end

	def cache_lookup(addr)
		@@cache.each_pair { |cidr_s, wd|
			wd.cidr.each { |cidr|
				if cidr.contains?(addr)
					@@log.debug "Cache hit for cidr=#{cidr_s} addr=#{addr}"
					return wd
				end
			}
		}
		return nil
	end

	def classify_addr(addr)
		@@log.debug "Classify addr >> #{addr}"
		wd = cache_lookup(addr)
		return wd unless wd.nil?

		wd = WhoisData.new(@wbc)
		begin
			sleep @sleep if @sleep > 0
			wd.classify_addr(addr)
			cache_put(wd)
			return wd
		rescue WhoisRateError => e
			@@log.error "Exceeded query rate for addr=#{addr}, slowing down: #{e.message}"
			@sleep += 5
			return classify_addr(addr)
		rescue => e
			@@log.error e.backtrace.join("\n")
			@@log.die "caught unhandled exception: #{e.to_s}"
		end
	end

	def classify_line(line)
		wd = WhoisData.new(@wbc)
		wd.classify_line(line)
		return wd
	end

	def classify_file(file)
		wd = WhoisData.new(@wbc)
		File.read(file).each_line { |line|
			wd.classify_line(line)
		}
		return wd
	end

	def classify(line)
		line=line.strip
		# %error 320 Exceeded query rate limit, wait 5s before trying again
		raise WhoisRateError, "Exceeded error rate: #{line}" unless line[/^%error.*?Exceeded query rate/].nil?
		@wbc.classify(line)
	end
end

