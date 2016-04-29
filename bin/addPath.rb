#!/usr/bin/env ruby

require 'optparse'

ME=File.basename($0, ".rb")

$opts={
	:append=>[],
	:prepend=>[]
}
optparser=OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]\n"

	opts.on('-a', '--append PATH', String, "") { |path|
		$opts[:append] << path
	}

	opts.on('-p', '--prepend PATH', String, "")  { |path|
		$opts[:prepend] << path
	}

	opts.on('-h', '--help', "Help") {
		$stdout.puts ""
		$stdout.puts opts
		exit 0
	}
}
optparser.parse!

path=ENV['PATH']
paths=path.split(/:/).uniq

$opts[:append].each { |p|
	if paths.include?(p)
		$stderr.puts "Path already contains #{p}, moving to end"
		paths.delete(p)
	end
	paths << p
}
$opts[:prepend].each { |p|
	if paths.include?(p)
		$stderr.puts "Path already contains #{p}, moving to beginning"
		paths.delete(p)
	end
	paths.unshift(p)
}

puts paths.uniq.join(':')

