#!/usr/bin/env ruby
#

require 'ip2location_ruby'
require 'json'
require 'logger' unless defined?(Logger)

class IP2Location
	IP2LOCATION_COUNTRY_LITE_DB1_BIN="~/Downloads/IP2LOCATION-LITE-DB1.BIN/IP2LOCATION-LITE-DB1.BIN"

	@@ip2location_lite_db1_bin = nil
	@@i2l = nil
	@@log = Logger.new(STDOUT)

	def self.init(opts)
		@@ip2location_lite_db1_bin = File.expand_path(opts[:ip2lcation_lite_db1_bin]||IP2LOCATION_COUNTRY_LITE_DB1_BIN)

		@@i2l = Ip2location.new.open(@@ip2location_lite_db1_bin) if File.exists?(@@ip2location_lite_db1_bin)

		@@log = opts[:logger]||@@log
	end

	MARK="§"
	def self.long(res)
		MARK+res[:country_long].to_s.strip
	rescue => e
		@@log.error e.to_s
		"unknown"+MARK
	end

	def self.short(res)
		res[:country_short].to_s.strip
	rescue => e
		@@log.error e.to_s
		"??"+MARK
	end

	def self.lookup(ip)
		{:ip_from=>2913992704, :country_short=>"CA", :country_long=>"Canada", :ip_to=>2914516992}
		result = {
			:country_short=>"",
			:country_long=>""
		}
		result = @@i2l.get_all(ip) unless @@i2l.nil?
		result
	end

end

#IP2Location.init({})
#rec=IP2Location.lookup("192.168.1.1")
#puts rec.inspect
