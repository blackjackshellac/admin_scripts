#!/usr/bin/env ruby
#

require 'nokogiri'
require 'net/http'
require 'uri'

LINK_DIR=File.expand_path("~/Videos/tor")

def read_uri(url)
  Net::HTTP.get(URI.parse(url))
rescue => e
  puts "Failed to read url: #{url}"
  exit 1
end

def read_title(content)
  Nokogiri::HTML(content).at('title').text
rescue => e
  puts "Failed to find title: #{e.to_s}"
  exit 1
end

url=ARGV[0]

Dir.mkdir(LINK_DIR, 0755) unless File.directory?(LINK_DIR)
Dir.chdir(LINK_DIR) {
  content = read_uri(url)
  title = read_title(content)

  puts "Title: #{title}"

  File.open("#{title}.tor", "wt") { |fd|
    fd.puts url
  }
}

