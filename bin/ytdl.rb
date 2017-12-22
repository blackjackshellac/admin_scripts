#!/usr/bin/env ruby
#
#

# dnf install taglib-devel
# gem install taglib-ruby
require 'taglib'
require 'readline'
require 'logger'
require 'optparse'
require 'json'
require 'open3'

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

$opts = {
	:genre => "xmas"
}
optparser=OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]\n"

	opts.on('-g', '--genre GENTRE', "Set the genre, default=#{$opts[:genre]}") { |genre|
		$opts[:genre]=genre
	}

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

#file="Queen - Thank God It's Christmas-6V5mtUff6ik"
# Queen - Thank God It's Christmas-6V5mtUff6ik
RE_FILE=/^\s*(?<artist>[^\-]+)\s*\-\s*(?<title>[^\-]+?)\(?(?<year>[12][90]\d\d)?\)?\s*\-\s*(?<code>.*)\s*$/
RE_DEST=/^\[ffmpeg\]\sDestination:\s*(?<filename>.*?)(?<ext>\.ogg)\s*$/m

#out=%{
#[youtube] l14aDp-4NKk: Downloading webpage
#[youtube] l14aDp-4NKk: Downloading video info webpage
#[youtube] l14aDp-4NKk: Extracting video information
#[youtube] l14aDp-4NKk: Downloading MPD manifest
#[download] Destination: The Pogues Featuring Kirsty MacColl - Fairytale Of New York-l14aDp-4NKk.m4a
#[download] 100% of 4.04MiB in 00:00
#[ffmpeg] Correcting container in "The Pogues Featuring Kirsty MacColl - Fairytale Of New York-l14aDp-4NKk.m4a"
#[ffmpeg] Destination: The Pogues Featuring Kirsty MacColl - Fairytale Of New York-l14aDp-4NKk.ogg
#Deleting original file The Pogues Featuring Kirsty MacColl - Fairytale Of New York-l14aDp-4NKk.m4a (pass -k to keep)
#}

def parse_out(out)
	m=RE_DEST.match(out)
	return {} if m.nil? || m[:filename].nil?
	$log.debug "match: #{m[:filename]}#{m[:ext]}"
	h={
		:file=>m[:filename]+m[:ext],
		:filename=>m[:filename],
		:ext=>m[:ext]
	}
	h
end

def parse_filename(filename)
	h={}
	m=RE_FILE.match(filename)
	return h if m.nil?
	[ :artist, :title, :code, :year ].each { |key|
		v=m[key]
		next if v.nil?
		$log.debug "metadata: #{key}=#{v}"
		h[key]=v.strip
	}
	h
end

def run_popen(cmd, opts={:echo=>true})
	puts cmd
	result={
		:out=>"",
		:exit_status=>1
	}
	Open3.popen2e(cmd) { |stdin, stdout_stderr, wait_thr|
		pid = wait_thr.pid # pid of the started process.
		stdin.close
		stdout_stderr.each { |line|
			puts line if opts[:echo]
			result[:out] << line+"\n"
		}
		result[:exit_status] = wait_thr.value # Process::Status object returned.
	}
 	result
end

def download_url(url, type=:vorbis, opts={})
	case type
	when :vorbis
		download_type(url, type, opts)
	else
		nil
	end
end

def download_type(url, type, opts)
	ytdl=opts[:ytdl]||""
	cmd=%/youtube-dl #{ytdl} -x --audio-format #{type.to_s} #{url}/
	#out=%x/#{cmd}/
	result = run_popen(cmd)
	raise "Command failed: #{cmd}" unless result[:exit_status] == 0
	result[:out]
end

TAG_FIELD_NAMES={
	:title => "TITLE",
	:album => "ALBUM",
	:artist=> "ARTIST",
	:genre => "GENRE",
	:year  => "DATE",
	:url   => "CONTACT"
}
SEP="="*80

def dump_data(data)
	puts SEP
	data.each_pair { |key, val|
		printf("%15s: %s\n", key.to_s, val.to_s)
	}
end

def dump_field_list(prefix, tag)
	puts SEP
	puts prefix unless prefix.nil? || prefix.empty?
	puts "Count: #{tag.field_count.to_s}"
	tag.field_list_map.each_pair { |key,val|
		#puts "%-15s: %s" % [ key.to_s, val.to_s ]
		printf("%15s: %s\n", key.to_s, val.to_s)
	}
end

def edit_field(key, data)
	raise "Field name must be given" if key.nil?
	key = key.to_sym
	raise "No data for field #{key}" unless data.key?(key)
	ans = Readline.readline("Enter new value for #{key} #{data[key]}>>> ")
	ans.strip!
	puts "Warning: field is empty" if ans.empty?
	data[key]=ans
rescue Interrupt => e
	puts "Aborting ..."
rescue => e
	puts e.message
ensure
	return data
end

def swap_field(key1, key2, data)
	raise "Two field names must be given" if key1.nil? || key2.nil?
	key1 = key1.to_sym
	key2 = key2.to_sym
	raise "No data for field #{key1}" unless data.key?(key1)
	raise "No data for field #{key2}" unless data.key?(key2)
	val = data[key1]
	data[key1] = data[key2]
	data[key2] = val
rescue Interrupt => e
	puts "Aborting ..."
rescue => e
	puts e.message
ensure
	return data
end

def edit_field_data(data)
	dump_data(data)
	while ans = Readline.readline("edit|swap|done|cancel >> ")
		ans.strip!
		case ans
		when /^edit\s*(.*?)?\s*$/
			data = edit_field($1, data)
			dump_data(data)
		when /^swap\s*(.*?)?\s*(.*?)?\s*$/
			data = swap_field($1, $2, data)
			dump_data(data)
		when /^done/
			break
		when /^cancel/
			data = {}
			break
		else
			puts "Unknown command: #{ans}"
		end
	end
rescue Interrupt => e
	puts "Aborting ..."
rescue => e
	$log.error e.message
ensure
	return data
end

def swap_title_artist?(data)
	if data.key?(:title) && data.key?(:artist)
		puts SEP
		[ :artist, :title ].each { |key|
			printf("%15s: %s\n", key.to_s, data[key])
		}
		ans = Readline.readline("Swap artist/title? (y/N) > ")
		if ans.eql?("y")
			artist=data[:title]
			data[:title]=data[:artist]
			data[:artist]=artist
		end
	end
	data
end

def tag_vorbis_file(filename, data)
	# Load a file

	$log.debug "filename: "+filename
	$log.debug "metadata: "+data.inspect

	TagLib::Ogg::Vorbis::File.open(filename) do |file|
		puts file.tag
		tag = file.tag

		dump_field_list("Before", tag)

		#data = swap_title_artist?(data)
		data = edit_field_data(data)

		tag.title   = data[:title]
		tag.artist  = data[:artist]
		tag.album   = data[:album]
		tag.genre   = data[:genre]
		tag.year    = data[:year].to_i if data.key?(:year)
		tag.comment = "youtube #{data[:code]}"

		tag.add_field(TAG_FIELD_NAMES[:url], data[:url], true) if data.key?(:url)

		dump_field_list("After", tag)

		#prop = file.audio_properties
		#puts prop.length
		#puts prop.bitrate

		file.save
	end

end

def process_url(url, opts)
	puts url
	out=download_url(url, :vorbis)

	filedata=parse_out(out)
	data=parse_filename(filedata[:filename])
	data[:genre]=opts[:genre]
	data[:url]=url
	data[:album]="youtube"
	tag_vorbis_file(filedata[:file], data)
end

#filename="[ffmpeg] Destination: Now That's What I Call Christmas 2018 - Old Classic Christmas Songs of All Time-oOlDchIOdA0.ogg"
#filedata=parse_out(filename)
#puts filename
#puts filedata.inspect
#data=parse_filename(filedata[:filename])
#data[:genre]="xmas"
#data[:url]="http://youtube.com"
#tag_vorbis_file(filedata[:file], data)

def run(cmd, args=nil)
	cmd="#{cmd} #{args}" unless args.nil? || args.empty?
	puts "run> "+cmd
	puts %x/#{cmd}/
end

RE_URL=/^https?.*/
RE_EASYTAG=/^easytag/
RE_FIND=/^find\s(.*)/
RE_LL=/^ll\s?(.*)/
RE_QUIT=/^quit/
if ARGV.empty?
	while cmd = Readline.readline("Enter url|find|easytag|ll|quit> ")
		cmd.strip!
		case cmd
		when RE_URL
			process_url(cmd, $opts)
		when RE_EASYTAG
			run("easytag", ".")
		when RE_FIND
			run("find -ls | grep -i \"#{$1}\"")
		when RE_LL
			run("ls -l", $1)
		when RE_QUIT
			break
		else
			puts "Unknown cmd #{cmd}"
		end
	end
	exit 0
end

puts ARGV.inspect
ARGV.each { |url|
	process_url(url, $opts)
}
