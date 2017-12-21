#!/usr/bin/env ruby
#
#

# dnf install taglib-devel
# gem install taglib-ruby
require 'taglib'
require 'readline'

#file="Queen - Thank God It's Christmas-6V5mtUff6ik"
# Queen - Thank God It's Christmas-6V5mtUff6ik
RE_FILE=/^\s*(?<artist>[^\-]+)\s*\-\s*(?<title>[^\-]+?)\(?(?<year>[12][90]\d\d)?\)?\s*\-\s*(?<code>.*)\s*$/
RE_DEST=/^\[ffmpeg\]\sDestination:\s*(?<filename>.*?)(?<ext>\.ogg)\s*$/m

$opts = {
	:genre => "xmas"
}

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
	puts "match: #{m[:filename]}#{m[:ext]}"
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
		puts "metadata: #{v}"
		h[key]=v.strip
	}
	h
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
	puts cmd
	out=%x/#{cmd}/
	out
end

url='https://www.youtube.com/watch?v=6V5mtUff6ik'

TAG_FIELD_NAMES={
	:title => "TITLE",
	:album => "ALBUM",
	:artist=> "ARTIST",
	:genre => "GENRE",
	:year  => "DATE",
	:url   => "CONTACT"
}
SEP="="*80

def dump_field_list(prefix, tag)
	puts SEP
	puts prefix unless prefix.nil? || prefix.empty?
	puts "Count: #{tag.field_count.to_s}"
	tag.field_list_map.each_pair { |key,val|
		#puts "%-15s: %s" % [ key.to_s, val.to_s ]
		printf("%15s: %s\n", key.to_s, val.to_s)
	}
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
	
	puts "filename: "+filename
	puts "metadata: "+data.inspect

	TagLib::Ogg::Vorbis::File.open(filename) do |file|
		puts file.tag
		tag = file.tag

		dump_field_list("Before", tag)

		data = swap_title_artist?(data)

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
	while cmd = Readline.readline("Enter url|find|easytag|ll> ")
		cmd.strip!
		break if cmd.empty?
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

