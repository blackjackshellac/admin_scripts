
require 'mail'

# log to maillog (@fdlog)
# log to Logger (@@log)
# log to console when opts[:echo]
class Rb2MuxLog
	RB2ML_SEP_LENGTH=50
	RB2ML_SEP="+"*RB2ML_SEP_LENGTH
	RB2ML_LOG_FORMAT="rb2_%Y%m%d_%H%M%S.txt"

	@@log = Logger.new(STDERR)
	@@tmp = "/var/tmp/rb2"

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)

		raise "opts :tmp not set" if opts[:tmp].nil?
		@@tmp = opts[:tmp]

		raise "opts :runtime not set" if opts[:runtime].nil?
		@@runtime=opts[:runtime]
		@@file = File.join(@@tmp, @@runtime.strftime(RB2ML_LOG_FORMAT))
	end

	attr_reader :file
	def initialize(opts)
		@client = nil
		@fdlog = nil
		@echo = nil
	end

	def open(opts, &block)
		@@log.debug "Opening #{@@file}"
		@fdlog = File.open(@@file, "w+")
		opts[:maillog]=self
		return @fdlog unless block_given?
		@@log.debug "Yeilding #{@fdlog}"
		yield(@fdlog)
	ensure
		@@log.debug "Closing #{@@file}"
		@fdlog.close
	end

	def close
		@fdlog.close unless @fdlog.nil?
		@fdlog = nil
	end

	def set_client(c)
		@client=c
	end

	def fmt_msg(type, msg)
		ts=Time.now.strftime("%Y%m%d_%H%M%S")
		c=@client.nil? ? " " : " [#{@client}] "
		"#{type}#{c}#{ts}: #{msg}"
	end

	def self.get_separator(msg)
		sep=""+RB2ML_SEP
		unless msg.nil?
			msg.strip!
			msg=" #{msg} "
			ml=msg.length
			sl=sep.length
			o=(sl-ml)/2.floor
			sep[o, ml]=msg if o > 0
		end
		sep
	end

	MUXLOG_OPTS_DEF={
		:echo=>false
	}
	def set_echo(echo=true)
		@echo=echo
	end

	def mopts(opts)
		opts.merge(MUXLOG_OPTS_DEF)
	end

	def mputs(type, msg, opts={})
		opts=mopts(opts)

		case type
		when :I
			@@log.info msg
		when :E
			@@log.error msg
		when :W
			@@log.warn msg
		when :D
			@@log.debug msg
		else
			raise "Unknown message type"
		end

		fmsg = fmt_msg(type, msg)

		echo=@echo||opts[:echo]
		puts fmsg if echo
		@fdlog.puts fmsg unless @fdlog.nil?
	end

	def separator(msg=nil, opts={})
		mputs :I, Rb2MuxLog.get_separator(msg), opts
	end

	def info(msg, opts={})
		mputs :I, msg, opts
	end

	def error(msg, opts={})
		mputs :E, msg, opts
	end

	def mail(opts)
		subj = opts[:subject]
		from = opts[:email_from]
		to   = opts[:email_to]
		body = File.read(@@file)
		mailer = Mail.new do
			from     from
			to       to
			subject  subj
			body     body
			#add_file :filename => File.basename(@@file), :content => File.read(@@file)
		end

		@@log.debug mailer.to_s
		mailer.deliver
	rescue => e
		emsg="Failed to mail result: #{opts.inspect} [#{e.to_s}]"
		self.error emsg, :echo=>true
		raise emsg
	end
end
