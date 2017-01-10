
class KeyDataTransaction
	FROM_TO_RE=/^(From|To)$/i
	ACCOUNTS_RE=/^(Chequing|Savings|Other\s+\d+\s+\w+)\s+(.*)/i
	KEY_COLON_DATA_RE=/^(?<key>.*?):(?<data>.*)$/
	KNOWN_KEYS_RE=/^(From|To|Amount|Date|Reference#)$/i

	@@log=Logger.new(STDERR)

	attr_reader :lastkey, :hdata, :order
	def initialize
		@lastkey=nil
		@hdata={}
		@order=[]
	end

	def self.init(opts={})
		@@log=opts[:logger] if opts.key?(:logger)
	end

	def self.process
		transa=[]
		trans=KeyDataTransaction.new
		begin
			@@log.info "Enter transaction data, type . to filter, Ctrl-C to quit"
			%x/stty -echo/
			ARGF.each { |line|
				line.strip!
				next if line.empty?
				break unless line[/^\s*\.\s*/].nil?
				@@log.debug "Process: [#{line}]"
				key=trans.process_line(line)
				if key.nil?
					trans.playback
					transa << trans
					trans=KeyDataTransaction.new
					key=trans.process_line(line)
					raise "Unexpected nil key in new transaction: [#{line}]" if key.nil?
				end
				trans.echo(key)
			}
			trans.playback
			transa << trans
		rescue Interrupt => e
			@@log.info "Caught interrupt, exiting"
			return nil
		rescue => e
			e.backtrace.each { |line|
				puts line
			}
			@@log.die e.to_s
		ensure
			%x/stty echo/
		end
		transa
	end

	def empty?
		@order.empty?
	end

	def process_line(line)
		return if line.strip.empty?
		m=line.match(KEY_COLON_DATA_RE)
		unless m.nil?
			# matched input of format "key: data"
			key=m[:key]
			data=m[:data]
			@@log.warn "Unknown data key>> [#{key}]" if key[KNOWN_KEYS_RE].nil?
			if @order.include?(key)
				@@log.warn "Key already recorded #{key}, create new transaction"
				return nil
			else
				@order << key unless @order.include?(key)
			end
			@lastkey=key
		else
			key=@lastkey
			if key.nil?
				@@log.error "Unexpected input, no key for input data=[#{line}] ... ignoring"
				# key=nil, ignore input
				line=""
			else
				@@log.warn "data not found for lastkey=#{key}" unless @hdata.key?(key)
				d=@hdata[key]||""
				line.prepend(d)
			end
			data=line
		end

		@hdata[key]=data.gsub(/\s+/, " ").strip
		key
	end

	def filter_data(key)
		# shouldn't happen
		raise "data hash has no output for key=#{key}" unless @hdata.key?(key)

		out=@hdata[key]

		return out if key[FROM_TO_RE].nil?

		# key is from or to
		if out[ACCOUNTS_RE].nil?
			out.gsub!(/\d/, "*")
		else
			acct=$1
			numb=$2.gsub(/\d/, "*")
			@@log.debug "Account=#{acct} number=#{$2} numb=#{numb}"
			out="%s %s" % [ acct, numb ]
		end

		out
	end

	def echo(key)
		return if key.nil?
		data=@hdata[key]
		return if data.nil? || data.empty?
		puts "#{key}: #{data}"
	end

	def playback(printkey=false)
		return if empty?

		puts "\n"
		@order.each { |key|
			out=filter_data(key)
			out.prepend("#{key}: ") if printkey
			puts out
		}
		puts "\n"
	end
end


