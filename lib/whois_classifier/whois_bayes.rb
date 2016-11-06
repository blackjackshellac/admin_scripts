#
#
#

require 'netaddr'

class WhoisBayes
	class WhoisRateError < StandardError
	end

	RE_WHOIS_COMMENT=/(.*)(%.*)$/
	RE_CAT=/([-\w]*):(.*)/

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

	def categorize(addr)
		$log.info ">>> whois #{addr}"
		WhoisData.whois(addr).each { |line|
			unless line[RE_WHOIS_COMMENT].nil?
				line = $1.strip
				wbc.train(:ignore, $2)
			end
			line.strip!
			next if line.empty?
			next if line[RE_CAT].nil?
			cat=$1.strip.downcase
			val=$2.strip

			next if @@unknown.keys.include?(cat)

			if WhoisData.is_ignore(cat)
				#puts "Debug: classify ignore #{cat}: #{line}"
				wbc.train(:ignore, line)
				next
			end
			kat = WhoisData.get_category(cat)
			unless kat.nil?
				@@log.info "classify #{cat} as #{kat}: #{line}"
				wbc.train(kat, line)
				next
			end
			@@unknown[cat] = line
			@@log.warn "#{cat} category not found in input: #{line}"
		}
	end

	def cache_lookup(addr)
		@@cache.keys.each { |cidr|
			return @@cache[cidr] if cidr.contains?(addr)
		}
		return nil
	end

	def classify_addr(addr)
		wd = cache_lookup(addr)
		return wd unless wd.nil?

		wd = WhoisData.new(@wbc)
		begin
			sleep @sleep if @sleep > 0
			wd.classify_addr(addr)
			return wd
		rescue WhoisRateError => e
			@@log.error "Exceeded query rate for addr=#{addr}, slowing down: #{e.message}"
			@sleep += 5
			return classify_addr(addr)
		rescue => e
			@@log.error e.backtrace.join('\n')
			@@log.die "caught unhandled exception: #{e.to_s}"
		end
	end

	def classify_file(file)
		wd = WhoisData.new(@wbc)
		File.read(file).each_line { |line|
			wd.classify_line(line)
		}
		if wd.cidr.nil?
		end
		#if cat == :cidr || cat.eql?(:cidr.to_s)
		#	puts "Info: cidr = #{line}"
		#	break
		#end
	end

	def classify(line)
		line=line.strip
		# %error 320 Exceeded query rate limit, wait 5s before trying again
		raise WhoisRateError, "Exceeded error rate: #{line}" unless line[/^%error.*?Exceeded query rate/].nil?
		@wbc.classify(line)
	end
end

