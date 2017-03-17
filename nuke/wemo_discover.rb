#!/usr/bin/env ruby

require 'socket'
require 'logger'

class WemoDiscover
	# LOCATION: http://192.168.0.21:49153/setup.xml
	LOCATION_RE=/LOCATION:\shttp:\/\/(?<addr>\d+\.\d+\.\d+\.\d+):(?<port>\d+)\/(?<path>.*)/

	# Simple Service Discovery Protocol (SSDP)
	# https://wiki.wireshark.org/SSDP
	# https://en.wikipedia.org/wiki/Simple_Service_Discovery_Protocol
	SSDP_ADDR = "239.255.255.250";
	SSDP_PORT = 1900;
	SSDP_MX = 10;
	# Wemo's uPnP implementation seems to be intentionally broken, security through obscurity?
	SSDP_ST = "urn:Belkin:device:controllee:1"
	SSDP_BROADCAST_ADDR=Addrinfo.udp(SSDP_ADDR, SSDP_PORT)

	SSDP_REQUEST = ""
	SSDP_REQUEST << "M-SEARCH * HTTP/1.1\r\n"
	SSDP_REQUEST << "HOST: %s:%d\r\n" % [SSDP_ADDR, SSDP_PORT]
	SSDP_REQUEST << "MAN: \"ssdp:discover\"\r\n"
	SSDP_REQUEST << "MX: %d\r\n" % SSDP_MX
	SSDP_REQUEST << "ST: %s\r\n" % SSDP_ST
	SSDP_REQUEST << "USER-AGENT: unix/5.1 UPnP/1.1 crash/1.0\r\n\r\n";

	@@log = Logger.new(STDOUT)
	@@log.level = Logger::INFO

	def self.debug(on=true)
		@@log.level = on ? Logger::DEBUG : Logger::INFO
	end

	def self.search(timeout = 5)
		addrs = []
		Socket.open(:INET, :DGRAM) { |sock|
			sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, 1)
			sock.send(SSDP_REQUEST, 0, SSDP_BROADCAST_ADDR)

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
					addrs << m[:addr]
				}
			end
		}
	rescue Interrupt => e
		@@log.info "Caught interrupt"
	rescue => e
		@@log.error "Caught exception #{e}"
	ensure
		return addrs
	end
end

#WemoDiscover::debug(false)
WemoDiscover::search(2).each { |addr| puts "Found wemo at #{addr}" }

