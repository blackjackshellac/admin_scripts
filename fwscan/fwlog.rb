#
# 
#

class FWLog
	REGEX_IPV4_ADDR="[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"
	REGEX_NOT_WS="[^\\s]*"
	REGEX_WORD_NUMBER="[\\w]+"
	REGEX_NUMBER="[\\d]+"
	REGEX_MAC="[\\da-fA-F:]+"

	@@log = nil

	FWLOG_KEYS = [ :ts, :home, :in, :out, :mac, :src, :dst, :proto, :tos, :ttl, :id, :spt, :dpt, :len ]
	attr_reader :entry
	attr_reader :ts, :home, :in, :out, :mac, :src, :dst, :proto, :tos, :ttl, :id, :spt, :dpt, :len
	def initialize(e)
		@entry = {}
		e.keys.each { |key|
			@entry[key] = e[key]
			instance_variable_set("@#{key}", e[key])
		}
	end

	def self.init(opts)
		@@log = opts[:logger]
		raise "Logger not set in FWLog" if @@log.nil?
	end

	def self.re_matcher(line, re)
		raise "match not found: #{line} [#{re.to_s}]" if line[re].nil?
		m=$1
		#@@log.debug "\t\tmatch=#{m} re=#{re.to_s}"
		return m
	end

	def self.parse_kernellog(line)
		#next if kernellog[/IN=([^\s])\s.*?MAC=([^\s]+)\s.*?SRC=(#{REGEX_IPV4_ADDR}).*?DST=(#{REGEX_IPV4_ADDR}).*?PROTO=([\w]+).*?SPT=([\d]+).*?DPT=([\d]+).*/].nil?

		#irb(main):005:0> f.split(/\s+/, 5)
		#=> ["Oct", "17", "10:52:01", "valium", "kernel: Shorewall:net2fw:DROP:IN=enp2s0 OUT= MAC=00:17:31:9c:91:6f:00:17:10:8e:27:16:08:00 SRC=60.48.47.237 DST=70.81.251.194 LEN=125 TOS=0x00 PREC=0x00 TTL=247 ID=36206 DF PROTO=UDP SPT=10003 DPT=34406 LEN=105"]

		mon,day,time,host,klog = line.split(/\s+/, 5)
		datetime=Time.parse("#{mon} #{day} #{time}")
		#@@log.debug ">> #{datetime} #{host}:\n\t#{klog}"

		e={}
		e[:ts]=datetime
		e[:host]=host
		e[:in]=re_matcher(klog, /^.*?IN=(#{REGEX_WORD_NUMBER})/)
		e[:out]=re_matcher(klog, /^.*?OUT=(#{REGEX_NOT_WS})/)
		e[:mac]=re_matcher(klog, /^.*?MAC=(#{REGEX_MAC})/)
		e[:src]=re_matcher(klog, /^.*?SRC=(#{REGEX_IPV4_ADDR})/)
		e[:dst]=re_matcher(klog, /^.*?DST=(#{REGEX_IPV4_ADDR})/)
		e[:proto]=re_matcher(klog, /^.*?PROTO=(#{REGEX_WORD_NUMBER})/)
		e[:tos]=re_matcher(klog, /^.*?TOS=(#{REGEX_WORD_NUMBER})/)
		e[:ttl]=re_matcher(klog, /^.*?TTL=(#{REGEX_NUMBER})/)
		e[:id] =re_matcher(klog, /^.*?ID=(#{REGEX_NUMBER})/)
		e[:spt]=re_matcher(klog, /^.*?SPT=(#{REGEX_NUMBER})/)
		e[:dpt]=re_matcher(klog, /^.*?DPT=(#{REGEX_NUMBER})/)
		e[:len]=re_matcher(klog, /^.*?LEN=(#{REGEX_NUMBER})/)
		e
	end

	def self.parse(line, opts)
		result={}
		return nil if opts.key?(:filter) && line[opts[:filter]].nil?
		return nil if opts.key(:in) && line[opts[:in]].nil?

		begin
			e = parse_kernellog(line)
			return FWLog.new(e)
		rescue => e
			@@log.error "Failed to parse kernel log entry: #{kernellog} [#{e}]"
			nil
		end
	end

	def to_json(*a)
		entry.to_json(*a)
	end
end


