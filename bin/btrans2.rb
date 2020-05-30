#!/usr/bin/env ruby
#

require 'logger'
require 'optparse'
require 'json'

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
end

def set_logger(stream)
	log = Logger.new(stream)
	log.level = Logger::INFO
	log.datetime_format = "%Y-%m-%d %H:%M:%S"
	log.formatter = proc do |severity, datetime, progname, msg|
		"#{severity} #{datetime}: #{msg}\n"
	end
	log
end

$log = set_logger(STDERR)

optparser=OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]\n"

	opts.on('-d', '--debug', "Enable debugging output") {
		$log.level = Logger::DEBUG
	}

	opts.on('-h', '--help', "Help") {
		$stdout.puts ""
		$stdout.puts opts
		exit 0
	}
}
optparser.parse!

class Transaction
	NOW_FMT="%Y-%m-%d %H:%M:%S"
	DAY_FMT="%b %d, %Y"
	ACCOUNTS="Other [0-9] .*?|Chequing|Savings|Personal Line of Credit"
	RE_BILL=/^\s*(Bill\s)(?<bill>\d+)\s*$/
	RE_REFN=/^\s*(Ref[#]:)\s*(?<refn>\d+)\s*([|] Cancel This Payment)?\s*$/
	RE_TRAN=/^\s*[\$](?<amt>[\d+\.,]+)\s(?<hbpt>has been paid to)\s(?<name>[\w\s\-]+)?\s([\(](?<alias>[\w\s\-]+)[\)]\s)?(?<number>[\w\-]+)\sfrom\s(?<acct>(#{ACCOUNTS}))\s(?<acctnum>[\d\s\-]+)\s*\./
	RE_DONE=/^\s*[\.]\s*$/

	TRANS_KEYS=[ :bill, :refn, :amt, :name, :alias, :number, :acct, :acctnum, :date ]

	RE_TRANS_FORMAT1=/^\s*Bill\s(?<bill>\d+)\s[$](?<amt>[\d+\.,]+)\s(?<hbpt>has been paid to)\s(?<name>[\w\s\-]+)?\s([\(](?<alias>[\w\s\-]+)[\)]\s)?(?<number>[\w\-]+)\sfrom\s(?<acct>(#{ACCOUNTS}))\s(?<acctnum>[\d\s\-]+)\s*[.]\sRef#: (?<refn>\d+)\s(?<cancel>[|]\sCancel This Payment)?/
	# May 20, 2020 Pending 656424 Cancel Payment
	RE_TRANS_FORMAT2=/^\s*(?<acct>#{ACCOUNTS})\s(?<acctnum>\d+\s[-\d]+)\s(?<name>[\w\s\-]+)?\s([\(](?<alias>[\w\s\-]+)[\)]\s)?(?<number>[\w\-]+)\s[$](?<amt>[\d+\.,]+)\s(?<date>\w+\s\d+[,]\s\d+)\s(?<pending>[[:alpha:]\s]+?)\s(?<refn>\d+)\s(?<cancel>Cancel Payment)\s*/

	FORMATS = {
		"Immediate" => RE_TRANS_FORMAT1,
		"Historical" => RE_TRANS_FORMAT2
	}

	@@log=Logger.new(STDERR)
	def self.init(opts={})
		@@log=opts[:logger] if opts.key?(:logger)
	end

	attr_reader :trans
	def initialize
		@trans={}
		@trans[:date]=Time.now.strftime(DAY_FMT)
	end

	def setmatchkey(key, m)
		val=@trans[key]
		if m.names.include?(key.to_s)
			val=m[key]
		elsif val.nil?
			@@log.error "match has no result for key=#{key}"
		end
		@trans[key]=val
	end

	def self.process_transactions(r, s, m)
		transactions = []
		while m
			# puts m.captures
			# puts m.names
			transaction = Transaction.new
			TRANS_KEYS.each { |key|
				transaction.setmatchkey(key, m)
			}
			transactions << transaction

			# end of entire match
			eom=m.end(0)
			# for some reason that I can grok r.match(s, eom) wasn't working
			# just skip forward in the string
			s=s[eom..]
			m = r.match(s)
		end
		transactions
	end

	def self.normalize_s(s)
		s.gsub(/\s+/, " ")
	end

	def self.grok_format(s)
		FORMATS.each_pair { |format, r|
			m = r.match(s)
			next if m.nil?
			@@log.info "Found #{format} format"
			return [ r, m ]
		}
		raise "Unsupported format"
	end

	def self.process_lines(lines)
		slines = lines.join(" ")
		slines = normalize_s(slines)

		r, m = grok_format(slines)
		process_transactions(r, slines, m)
	end

	def self.end_input(line)
		RE_DONE.match(line).nil? ? false : true
	end

	def self.read_input()
		lines=[]
		while true
			begin
				line = gets
			rescue Interrupt => e
				# jump out on interrupt
				line="."
			rescue => e
				raise e
			end

			break unless line
			line.strip!

			if line.empty?
				$log.debug "Ignoring empty line"
				next
			end

			puts ">> #{line}"
			if Transaction.end_input(line)
				$log.debug "Found end of input"
				break
			end

			lines << line
		end

		lines
	end

	def self.summarize(transactions)
		@@log.info "Summarizing transactions ...\n" unless transactions.empty?
		transactions.each { |trans|
			trans.summary
		}
	end

    # 0123-45678-999991234
    # (^|\s)[-\d]{4}(?<digits>[-\d]+?)[-\d]*(\s|$)
    RE_OBF=/^(?<lead>[a-zA-Z\s]*?[-\d]{4})(?<digits>[-\d]+?)(?<tail>[-\d]{4})(\s|$)/
    def obfuscate_digits(val)
      m=RE_OBF.match(val)
      unless m.nil?
        #puts m[:lead]
        #puts m[:digits]
        #puts m[:tail]
        val=m[:lead]+m[:digits].gsub(/\d/, "*")+m[:tail]
      end
      val
    end

	def summary
		if @trans.empty?
			$log.debug "Ignoring empty transaction"
			return
		end

		name=@trans[:alias].nil? ? @trans[:name] : ("%s (%s)" % [ @trans[:alias], @trans[:name] ])
		trans[:name_alias]=name

		@trans[:alias] = @trans[:name] if @trans[:alias].nil?

		[ :acct, :name_alias, :amt, :date, :refn ].each { |key|
			val=@trans[key]
			if val.nil?
				puts "WARNING: Trans value not found for \'#{key}\'"
			else
				puts obfuscate_digits(val)
			end
		}
		puts
	end

	def empty?
		@trans.empty?
	end
end

Transaction.init( :logger => $log )

$log.info "Paste transaction and hit Ctrl-D to process"

def join_last(lines, line, sep="")
	$log.die "Can't concatonate element to empty array: #{line}" if lines.length < 1

	# append this line to the previous line if it doesn't end in Bill|Ref#|$
	line=lines.delete_at(-1)+sep+line
	$log.info "Updated '#{line}'"
	line
end

lines=Transaction.read_input
$log.die "No lines to process" if lines.empty?

begin
  transactions = Transaction.process_lines(lines)
  Transaction.summarize(transactions)
rescue => e
  puts e.backtrace.join("\n")
  $log.err e.to_s
  exit 1
end

