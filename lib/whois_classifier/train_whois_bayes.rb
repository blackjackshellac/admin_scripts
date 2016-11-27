#!/usr/bin/env ruby
#

require 'fileutils'
require 'classifier-reborn'
require 'json'

me=File.symlink?($0) ? File.readlink($0) : $0
ME=File.basename($0, ".rb")
MD=File.dirname(me)
LIB=File.realpath("..")

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")
TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)

RE_SPACES=/\s+/
RE_COMMENT=/#.*$/
RE_DELIMS=/[\s,;:]+/
RE_IPV4=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")
require_relative File.join(LIB, "runner")
require_relative "whois_bayes.rb"
require_relative "whois_data.rb"
require_relative "command_shell"

#$cat = %w/abuse-c abuse-mailbox address admin-c country created descr fax-no inetnum last-modified mnt-by mnt-ref netname nic-hdl org organisation org-name org-type origin phone remarks role route source status tech-c/

$log=Logger::set_logger(STDERR)

$opts = {
		:addresses => [],
		:file => nil,
		:data => File.join(TMP, "trained_classifier.dat"),
		:logger => $log,
		:train => false,
		:retrain => false,
		:classify => false,
		:shell => false,
		:format => WhoisData::FORMATS.keys[0],
		:log => nil,
		:whois_cache => File.join(TMP, "whois_cache.json")
}

$opts = OParser.parse($opts, "") { |opts|
	opts.on('-t', '--train', "Train classifier data using given addresses") {
		$opts[:train] = true
	}

	opts.on('-c', '--classify', "Classify given addresses") {
		$opts[:classify] = true
	}

	opts.on('-s', '--shell', "Command shell for training, classifying input") {
		$opts[:shell] = true
	}

	opts.on('--retrain', "Retrain the classifier and backup classifier data") {
		$opts[:retrain] = true
	}

	opts.on('-a', '--addr LIST', Array, "One or more addresses to use for training") { |list|
		list.each { |addr|
			addr.strip!
			raise "The given address does not appear to be a valid IPV4 address: #{addr}" if addr[RE_IPV4].nil?
			$opts[:addresses] << addr.strip
		}
	}

	opts.on('-i', '--input FILE', String, "Input file containing addresses for training, - for stdin") { |file|
		$opts[:file] = file
	}

	opts.on('--data FILE', String, "Classifier data, default #{$opts[:data]}") { |file|
		$opts[:data]=file
	}

	opts.on('-l', '--log FILE', String, "Optional log file") { |file|
		$opts[:log]=file
	}

	opts.on('-f', '--format FORMAT', String, "Output formats [#{WhoisData::FORMATS.keys.join(",")}], default #{$opts[:format]}") { |format|
		$opts[:format] = format.to_sym
	}
}

if File.exists?($opts[:data])
	if $opts[:retrain]
		now=%x/date +"%Y%m%d-%H%M%S"/.strip
		src=$opts[:data]
		ext=""
		if !src[/^(.*)(\..*$)/].nil?
			src=$1
			ext=$2
		end
		dst="%s.%s%s" % [ src, now, ext ]
		puts FileUtils.mv $opts[:data], dst, :verbose=>true
	end
else # training data file doesn't exist, make sure we are training
	$opts[:train] = true
	$opts[:classify] = false
end

unless $opts[:log].nil?
	$log=Logger::set_logger($opts[:log])
	$log.level = Logger::DEBUG if $opts[:debug]
	$opts[:logger]=$log
end

def readfile(file, &block)
	input = "-".eql?(file) ? $< : File.new(file, "r")
	input.each { |line|
		yield(line)
	}
end

unless $opts[:file].nil?
	#lines = File.read($opts[:file]).split(/\n/)
	readfile($opts[:file]) { |line|
		line.gsub!(RE_SPACES, " ")
		line.gsub!(RE_COMMENT, "")
		line.strip!
		addrs = line.split(RE_DELIMS)
		$log.debug "addrs=#{addrs.inspect}"
		addrs.each { |addr|
			next if addr.empty?
			if addr[RE_IPV4].nil?
				$log.error "Invalid ip address: #{addr}"
				next
			end
			$log.debug "Adding #{addr}"
			$opts[:addresses] << addr
		}
	}
end

WhoisBayes.init($opts)
WhoisData.init($opts)
WhoisData.load_cache

if File.exists?($opts[:data])
	wb = WhoisBayes.loadTraining($opts[:data])
else
	wb = WhoisBayes.new
end
$log.debug "Categories: #{wb.wbc.categories}"

if $opts[:shell]
	fopts={
		:stream=>$stdout,
		:headers=>true
	}

	COMMANDS = %w/train classify whois fetch run history help quit /
	HELP = {
		:train => {
			:args => "",
			:help => "Train given input"
		},
		:classify => {
			:args => "",
			:help => "Classify given input"
		},
		:whois => {
			:args => "<addr>|pop",
			:help => "Send whois output to train or classify, can pop from address stack filled with fetch"
		},
		:fetch => {
			:args => "host",
			:help => "fetch addresses using fwscan.rb, see whois to pop for training or classifying"
		},
		:run => {
			:args => "",
			:help => "Run the given command"
		},
		:history => {
			:args => "",
			:help => "Command history"
		},
		:help => {
			:args => "",
			:help => "Help for commands [#{COMMANDS.join(',')}]"
		},
		:quit => {
			:args => "",
			:help => "Quit the shell and exit"
		}
	}

	train_proc = Proc.new { |cli|
		$log.debug "Called proc train: #{cli.class}"
		cli.prompt "train"
	}

	classify_proc = Proc.new { |cli|
		cli.prompt "classify"
	}

	history_proc = Proc.new { |cli|
		cli.history
	}

	help_proc = Proc.new { |cli|
		puts cli.commands.join(", ")
		args = cli.args
		args = "" if args.nil? || args.empty?
		unless args.empty?
			# TODO implement help output from cli.help[args]
			puts cli.get_help(args.split(/\s+/)[0])
		end
	}

	quit_proc = Proc.new { |cli|
		cli.action = :quit
	}

	execute_proc = Proc.new { |cli, line|
		$log.debug "Execute line=#{line}, action=#{cli.action}"
		case cli.action 
		when :train
			cat,val = WhoisData.cat_from_line(line)
			if cat.nil?
				puts "No category specified in input #{line}: [#{WhoisData.cat_keys.join(", ")}]"
			else
				kat = wb.train_cat_line(cat, val)
			end
		when :classify
			wd = wb.classify_line(line)
			wd.classify_cleanup
			$log.info "Classified line as #{wd.line_cat}: #{line}"
			wd.to_format($opts[:format], fopts)
		else
			$log.error "Unknown action: #{cli.action}"
		end
	}

	whois_proc = Proc.new { |cli, args|
		$log.debug "Called whois_proc #{args}"
		case cli.action
		when :train
			wb.categorize(args)
		when :classify
			fopts={
				:stream=>$stdout,
				:headers=>true
			}
			wd = wb.classify_addr(args, false)
			wd.to_format($opts[:format], fopts)
		else
			$log.info "Invalid action for whois: #{cli.action}"
		end
	}

	# run command to stdout
	run_proc = Proc.new { |cli, args|
		$log.debug "Called run_proc #{args}"
		Runner.run3(args)
	}

	# run command and fetch lines to stdout
	fetch_proc = Proc.new { |cli, args|
		$log.debug "Called fetch #{args}"
		opts={
			:lines=>[],
			:echo=>true
		}
		a=args.split(/\s+/, 2)
		if a.length < 1
			$log.error "Argument is host to scan"
		else
			err = Runner.run3(%Q/fwscan.rb -S #{a[0]} -k "24 hours ago" -o - -f csv --no-headers | cut -f1 -d','/, opts)
			cli.stack.concat(opts[:lines]) if err == 0 && opts[:lines].length > 0
			cli.stack.sort!.uniq!
		end
	}

	completion_proc = Proc.new { |s|
		commands = CommandShell::CLI.commands
		commandh = CommandShell::CLI.commandh
		s=s.strip
		$stderr.puts "[#{s}]"
		if s.empty?
			puts commands.join(", ")
		elsif commandh.key?(s)
			s=commandh[s]
		else
			s=nil
		end
		s
	}

	CommandShell::CLI.init($opts)

	cli = CommandShell::CLI.new(execute_proc,
								:commands=>COMMANDS,
								:help=>HELP,
								:completion=>completion_proc,
							    :append_char=>" ",
							    :word_break_char=>"")

	$opts[:classify] ? classify_proc.call(cli) : train_proc.call(cli)

	cli.command_proc("train", train_proc)
	cli.command_proc("classify", classify_proc)
	cli.command_proc("whois", whois_proc)
	cli.command_proc("run", run_proc)
	cli.command_proc("fetch", fetch_proc)
	cli.command_proc("history", history_proc)
	cli.command_proc("help", help_proc)
	cli.command_proc("quit", quit_proc)
	cli.shell
	exit
end

if $opts[:train]
	$opts[:addresses].each { |addr|
		wb.categorize(addr)
	}
	wb.saveTraining($opts[:data])

	unknown = WhoisBayes.unknown
	unless unknown.empty?
		arr='%w/'
		unknown.keys.each { |key|
			arr+=key+" "
		}
		arr=arr.strip+'/'
		$stderr.puts arr
	end
end

if $opts[:classify]
	fopts={
		:stream=>$stdout,
		:headers=>true
	}
	$opts[:addresses].each { |addr|
		wd = wb.classify_addr(addr)
		wd.to_format($opts[:format], fopts)
		fopts[:headers]=false
	}
end

WhoisData.save_cache

#tests=[
#	"inetnum:        70.81.251.0 - 70.81.251.255",
#	"inetnum:        213.202.232.0 - 213.202.235.255"
#]
#tests.each { |test|
#	cat=wb.classify test
#	puts "Classified as #{cat}: #{test}"
#}

#wd = wb.classify_file("whois_sample.txt")
#puts JSON.pretty_generate(wd)

#wbc.train_interesting "here are some good words. I hope you love them"
#wbc.train_uninteresting "here are some bad words, I hate you"
#puts wbc.classify "I hate bad words and you are good" # returns 'Uninteresting'

#classifier_snapshot = Marshal.dump wbc

# This is a string of bytes, you can persist it anywhere you like
#
# File.open("classifier.dat", "w") {|f| f.write(classifier_snapshot) }
# # Or Redis.current.save "classifier", classifier_snapshot
#
# # This is now saved to a file, and you can safely restart the application
# data = File.read("classifier.dat")
# # Or data = Redis.current.get "classifier"
# trained_classifier = Marshal.load data
# trained_classifier.classify "I love" # returns 'Interesting'
