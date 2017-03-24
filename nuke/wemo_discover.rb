#!/usr/bin/env ruby

require 'socket'
require 'logger'
require 'uri'
require 'net/http'

class WemoDiscover
	# LOCATION: http://192.168.0.21:49153/setup.xml
	LOCATION_RE=/LOCATION:\shttp:\/\/(?<addr>\d+\.\d+\.\d+\.\d+):(?<port>\d+)\/(?<path>.*?)$/

	# Simple Service Discovery Protocol (SSDP)
	# https://wiki.wireshark.org/SSDP
	# https://en.wikipedia.org/wiki/Simple_Service_Discovery_Protocol
	SSDP_ADDR = "239.255.255.250";
	SSDP_PORT = 1900;
	SSDP_MX = 10;
	# Wemo's uPnP implementation seems to be intentionally broken, security through obscurity?
	SSDP_ST = "urn:Belkin:device:controllee:1"
	SSDP_BROADCAST_ADDR=Addrinfo.udp(SSDP_ADDR, SSDP_PORT)

	@@log = Logger.new(STDOUT)
	@@log.level = Logger::INFO

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.getSSDPRequest(st=SSDP_ST)
		ssdp_request = ""
		ssdp_request << "M-SEARCH * HTTP/1.1\r\n"
		ssdp_request << "HOST: %s:%d\r\n" % [SSDP_ADDR, SSDP_PORT]
		ssdp_request << "MAN: \"ssdp:discover\"\r\n"
		ssdp_request << "MX: %d\r\n" % SSDP_MX
		ssdp_request << "ST: %s\r\n" % st
		ssdp_request << "USER-AGENT: unix/5.1 UPnP/1.1 crash/1.0\r\n\r\n";
		@@log.debug "request=\n#{ssdp_request}"
		ssdp_request
	end

	def self.debug(on=true)
		@@log.level = on ? Logger::DEBUG : Logger::INFO
	end

	def self.getFriendlyName(url)
		uri = URI(url)
		@@log.debug "uri=#{uri.to_s}"
		res = Net::HTTP.get_response(uri)
		return nil unless res.code.eql?('200')
		body=res.body
		body.split(/\n/).each { |line|
			# <friendlyName>Gilgamesh</friendlyName>
			# poor man's xml parser
			m = line.match(/\<friendlyName\>(?<fname>.*?)\<\/friendlyName\>/)
			return m[:fname] unless m.nil?
		}
		nil
	end

	def self.search(timeout = 5)
		addrs = {}
		Socket.open(:INET, :DGRAM) { |sock|
			sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, 1)
			sock.send(getSSDPRequest, 0, SSDP_BROADCAST_ADDR)

			while true
				ready = IO.select([sock], nil, nil, timeout)
				break unless ready
				sock.recv_nonblock(1024).split(/\n/).each { |line|
					# -- example --
					#HTTP/1.1 200 OK
					#CACHE-CONTROL: max-age=86400
					#DATE: Sun, 12 Mar 2017 13:35:47 GMT
					#EXT:
					#LOCATION: http://192.168.0.21:49153/setup.xml
					#OPT: "http://schemas.upnp.org/upnp/1/0/"; ns=01
					#01-NLS: 7f9a0c3e-1dd2-11b2-aef9-de6f22c3c5e9
					#SERVER: Unspecified, UPnP/1.0, Unspecified
					#X-User-Agent: redsonic
					#ST: urn:Belkin:device:controllee:1
					#USN: uuid:Socket-1_0-221425K0100445::urn:Belkin:device:controllee:1

					@@log.debug line
					m = line.match(LOCATION_RE)
					next if m.nil?
					# TODO download and parse data from setup.xml, for now we'll just use the addr from LOCATION:
					@@log.debug "Found wemo: #{m[:addr]} on port #{m[:port]} with path #{m[:path]}"
					url="http://#{m[:addr]}:#{m[:port]}/#{m[:path].strip}"
					addrs[m[:addr]]={
						:url=>url
					}
				}
			end
		}

		addrs.each_pair { |addr,val|
			fn = getFriendlyName(val[:url])
			@@log.debug "friendlyName=#{fn}"
			val[:fname]=fn
		}

	rescue Interrupt => e
		@@log.info "Caught interrupt"
	rescue => e
		@@log.error "Caught exception #{e}"
		e.backtrace.each { |line|
			puts line
		}
	ensure
		return addrs
	end

	def self.connect(host)
		@@log.info "Connecting to #{host}"
		switch = Wemote::Switch.new(host)
	rescue Interrupt => e
		@@log.info "Caught interrupt"
		switch = nil
	rescue => e
		@@log.error "Caught exception #{e}"
		switch = nil
	ensure
		switch
	end
end

#WemoDiscover::debug(false)
#WemoDiscover::search(2).each_pair { |addr, val|
#	puts "Found wemo #{val[:fname]} at #{addr}"
#}

