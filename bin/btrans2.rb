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
	ACCOUNTS="Other 2 JOINT|Chequing|Savings"
	RE_BILL=/^\s*(Bill\s)(?<bill>\d+)\s*$/
	RE_REFN=/^\s*(Ref[#]:)\s*(?<refn>\d+)\s*([|] Cancel This Payment)?\s*$/
	RE_TRAN=/^\s*[\$](?<amt>\d+\.\d+)\s(?<hbpt>has been paid to)\s(?<name>[A-Za-z\s]+)?\s[\(](?<alias>[A-Za-z\s]+)[\)]\s(?<number>\d+)\sfrom\s(?<acct>(#{ACCOUNTS}))\s(?<acctnum>[\d\s\-]+)\s*\./
	RE_DONE=/^\s*[\.]\s*$/

	@@log=Logger.new(STDERR)
	def self.init(opts={})
		@@log=opts[:logger] if opts.key?(:logger)
	end

	attr_reader :bill, :trans, :refn
	def initialize
		@trans={}
		@bill=nil
		@refn=nil
	end

	def process(line)
		@@log.debug "Processing>> #{line}"

		m=RE_BILL.match(line)
		unless m.nil?
			@@log.debug "Found Bill# match for #{line}: "+m[:bill]
			@bill=m[:bill]
			return true
		end

		m=RE_TRAN.match(line)
		unless m.nil?
			raise "transaction is not empty: #{@trans.inspect}" unless @trans.empty?
			now=Time.now
			@trans[:date]=now.strftime(DAY_FMT)
			if @bill.nil?
				@@log.warn "No bill found for transaction, using #{now}"
				@bill=now.strftime(NOW_FMT)
			end
			[ :amt, :name, :alias, :number, :acct, :acctnum ].each { |key|
				@trans[key]=m[key]
			}
			@@log.debug "Found Transaction match for #{line}: %s/%s/%s/%s/%s/%s" % [ m[:amt], m[:name], m[:alias], m[:number], m[:acct], m[:acctnum] ]
			return true
		end

		m=RE_REFN.match(line)
		unless m.nil?
			@refn=m[:refn]
			@@log.debug "Found Ref# match for #{line}: #{@refn}"
			raise "No transaction found for ref# #{@refn}" if @trans.empty?
			raise "No bill found for ref#" if @bill.nil?
			@trans[:bill]=@bill
			@trans[:refn]=@refn
			@@log.debug JSON.pretty_generate(@trans)
			return true
		end
		false
	end

	def self.end_input(line)
		m=RE_DONE.match(line)
		(m.nil? ? false : true)
	end

	def done
		#!@trans.empty? && @trans.key?(:bill) && @trans.key(:refn)
		return false if @trans.empty? || @bill.nil? || @refn.nil?
		@@log.debug "Transaction is complete"
		true
	end

	def summary
		puts @trans[:acct]
		puts "%s (%s)" % [ @trans[:alias], @trans[:name] ]
		puts "$#{@trans[:amt]}"
		puts @trans[:date]
		puts @trans[:refn]
		puts
	end
end

Transaction.init( :logger => $log )

$log.info "Paste transaction and hit Ctrl-D to process"

lines=[]
while line = gets
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

transactions=[]
trans=Transaction.new
lines.each { |line|
	if trans.process(line)
		if trans.done
			$log.info "Transaction finished"
			transactions << trans
			trans=Transaction.new
		end
	else
		$log.warn "No match for line #{line}, ignoring"
	end
}

$log.info "Summarizing transactions ...\n"
transactions.each { |trans|
	trans.summary
}
