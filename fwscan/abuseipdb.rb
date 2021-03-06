
require 'uri'
require 'cgi'
require 'net/http'
require 'tempfile'
require 'json'
require 'fileutils'
require 'resolv'

class String
  def truncate(max)
	 length > max ? "#{self[0...max]}..." : self
  end

  def ipaddress?
	  self[/^(?:(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])(\.(?!$)|$)){4}$/].nil? ? false : true
  end
end

class AbuseIPDB
	ABUSEIPDB_DOM="https://www.abuseipdb.com"
	ABUSEIPDB_CHECK="/check/%s/json"
	ABUSEIPDB_REPORT="/report/json"
	CATEGORIES = {
		:PORT_SCAN => 14,
		:HACKING => 15
	}
	#ABUSEIPDB_URL="https://www.abuseipdb.com/%s/json?key=%s&days=%s"

	@@api_key=nil
	@@log = Logger.new(STDOUT)

	@@memoizer_file = {
		:check => nil,
		:report => nil
	}
	#@@memoizer_check = nil
	#@@memoizer_report = nil
	@@memoizer_data = {
		:check => {},
		:report => {}
	}
	#@@memoizer_check_data = {}
	#@@memoizer_report_data = {}

	def initialize
	end

	def self.load_memoizer(action)
		return if @@memoizer_file[action].nil? || !File.exists?(@@memoizer_file[action])

		json = File.read(@@memoizer_file[action])
		memoizer = JSON.parse(json, :symbolize_names => true)
		now = Time.now.to_i
		# check them once per day
		timeout = 86400
		puts "before "+memoizer.count.to_s
		memoizer = memoizer.delete_if { |ip, result|
			if result[:time].nil?
				puts "Warning: age of record not set, deleting: "+result.inspect
			else
				age=now-result[:time]
				delete=(age > timeout)
				str=delete ? "deleting" : "keeping"
				puts "#{str} ip=#{ip} time=#{result[:time]} now=#{now} age=#{age}"
			end
			delete
		}
		# convert hash key symbols to strings
		raise " fuck " if @@memoizer_data[action].nil? && @@memoizer_data[action].class != Hash
		memoizer.each_pair { |ip,result|
			@@memoizer_data[action][ip.to_s]=result
		}
		puts "after "+@@memoizer_data[action].count.to_s
	end

	# action is :check or :report
	def self.save_memoizer(action)
		file=@@memoizer_file[action]
		data=@@memoizer_data[action]
		return if file.nil?
		raise "memoizer_data is nil for action=#{action.inspect}" if data.nil?
		puts " >> saving "+file
		File.open(file, "w") { |fd|
			data.each_pair { |ip, result|
				next unless result[:time].nil?
				puts "Missing timestamp in result: #{result.inspect}"
				result[:time]=Time.now.to_i
			}
			fd.puts JSON.pretty_generate(data)
		}
	end

	def self.init(opts)
		@@log = opts[:logger] unless opts[:logger].nil?
		@@api_key = opts[:ipdb_apikey] unless opts[:ipdb_apikey].nil?
		@@log.info "API KEY=#{@@api_key}"

		username=ENV['LOGNAME']||ENV['USERNAME']||ENV['USER']
		dirname=(username.nil? ? "/var/tmp" : "/var/tmp/#{username}")
		FileUtils.mkdir_p dirname

		[:check, :report].each { |action|
			@@memoizer_file[action] = "#{dirname}/abuseipdb_#{action}.json"
			load_memoizer(action)
		}

	end

	def self.apikey(key)
		@@api_key=key
	end

	def self.get_category(categories, entry)
		category = entry["category"]
		categories.concat(category) unless category.nil?
	end

	def self.get_categories(resp)
		#puts "#{resp.class}="+resp.inspect
		categories=[]
		resp.each { |entry|
			get_category(categories, entry)
		}
		categories.uniq.sort
	end

	# find the first hash in resp array with the specified key (as a string)
	def self.get_resp_value(resp, key)
		# make sure key is a string
		key = key.to_s
		resp.each { |entry|
			return entry[key] if entry.key?(key)
		}
		return ""
	end

	def self.summarise_result(result, fwla, stream, prefix="")
		ip = result[:ip]
		if result[:error].nil?
			count=result[:raw].count
			fwlac = (fwla.nil? || fwla.empty?) ? 0 : fwla.count

			res=IP2Location.lookup(ip)
			ip2loc_country = IP2Location.long(res)
			ip2loc_isoCode = IP2Location.short(res)

			country = result[:country]
			isoCode = result[:isoCode]
			categories = result[:categories]||[]

			if country.nil? || country.empty?
				country = ip2loc_country
			else
				# compare with ip2loc_country but skip the mark character
				unless country.eql?(ip2loc_country[1..-1])
					country += ": #{ip2loc_country}" unless ip2loc_country.empty?
				end
			end
			if isoCode.nil? || isoCode.empty?
				isoCode = ip2loc_isoCode
			else
				#stream.puts ".#{isoCode}. .#{ip2loc_isoCode}."
				unless isoCode.eql?(ip2loc_isoCode)
					isoCode += ": #{ip2loc_isoCode}" unless ip2loc_isoCode.empty?
				end
			end
			stream.puts "%s%15s (%d) - [%d] %s (%s) [%s]" % [ prefix, ip, fwlac, count, isoCode, country, categories.join(",") ] if count > 0 || fwlac  > 0
		else
			stream.puts "%s%15s Error: #{result[:error]}" % [ prefix, result[:ip] ]
			stream.puts result.to_json
			#stream.puts JSON.pretty_generate(result)
		end
	end

	def self.summarise_results(results, stream, opts)
		return if results.empty?

		entries = opts[:entries]||{}

		# results_by_count is an array like
		# [ [ ip0, { # result0 } ], [ ip1, { #result1 } ], ... ]
		results_by_count = results.sort_by { |ip, result|
			result.key?(:raw) ? result[:raw].count : 0
		}

		stream.puts " AbuseIPDB Summary ".center(50, "+")

		results_by_count.each { |item|
			result=item[1]
			ip=result[:ip]
			fwla=entries[ip]||[]
			AbuseIPDB.summarise_result(result, fwla, stream)
		}

	end

	def self.memoized(ip, action)
		@@memoizer_data[action][ip]
	end

	def self.check(ip)
		return { :error=> "API key not set" } if @@api_key.nil?

		result = memoized(ip, :check)
		if !result.nil?
			puts "Address is already scanned: #{ip}"
			return result
		end

		puts "AbuseIPDB: checking #{ip}"
		params = {
			:key=>@@api_key,
			:days=>30
		}
		uri_str = "#{ABUSEIPDB_DOM}#{ABUSEIPDB_CHECK % ip}?"+params.map{|k,v| "#{k}=#{CGI::escape(v.to_s)}"}.join('&')
		uri = URI(uri_str)

		puts uri.to_s
		#puts uri.inspect

		#
		#{
		#  "ip": "148.153.35.50",
		#  "category": [
		#    14
		#  ],
		#  "created": "Wed, 28 Mar 2018 10:02:09 +0000",
		#  "country": "United States",
		#  "isoCode": "US",
		#  "isWhitelisted": false
		#}
		#

		result = {
			:ip=>ip,
			:categories=>[],
			:country=>"",
			:isoCode=>"",
			:raw=>[],
			:error=>nil,
			:time=>Time.now.to_i,
			:success=>false
		}
		begin
		Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https', :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
			request = Net::HTTP::Get.new uri.request_uri
			response = http.request request
			#puts response.inspect
			json=response.body
			if json.empty?
				result[:error]={
					"status"=>1,
					"code"=>1,
					"title"=>"empty response"
				}
			end
			begin
				resp=JSON.parse(json) #, :symbolize_names => true)
				case resp
				when Array
					if resp[0] && (resp[0].key?("status") || resp[0].key?("code"))
						#[
						#  {
						#    "id": "Too Many Requests",
						#    "links": {
						#      "about": "https://www.abuseipdb.com/api"
						#    },
						#    "status": "429",
						#    "code": "1050",
						#    "title": "The user has sent too many requests in a given amount of time.",
						#    "detail": "You have exceeded the rate limit for this service."
						#  }
						#]
						result[:error]=resp[0]
					end
				when Hash
					# make sure response is an Array
					resp = [ resp ]
				else
					@@log.error "Unknown resp class: #{resp.class}"
					resp=[]
				end

				unless resp.empty?
					result[:raw].concat(resp)
					result[:categories].concat(get_categories(resp))
					result[:categories].uniq!

					[:country, :isoCode].each { |key|
						result[key]=get_resp_value(resp, key)
					}
					result[:success]=true
				end

			rescue => e
				@@log.error "Failed to parse json response: #{json}"
				@@log.error e.to_s
			end
		end
		if result[:error].nil? && !result[:raw].empty? && result[:success]
			result[:time] = Time.now.to_i
			@@memoizer_data[:check][ip]=result

			save_memoizer(:check)
		end
		rescue Net::ReadTimeout => e
			result[:error]=e.message
		rescue => e
			result[:error]=e.message
		end
		result
	end

	# https://www.abuseipdb.com/report/json?key=[API_KEY]&category=[CATEGORIES]&comment=[COMMENT]&ip=[IP]
	def self.report(ip, categories, comment, opts)
		return { :error=> "API key not set" } if @@api_key.nil?

		result = memoized(ip, :report)
		if !result.nil?
			@@log.info "Address is already scanned: #{ip}"
			return @@memoizer_data[:report][ip]
		end

		categories = categories.split(/\s*,\s*/) if categories.class == String

		return { :error => "param categories should be an Array or a String" } if categories.class != Array

		stream = opts[:stream]||STDOUT

		stream.puts "AbuseIPDB: reporting #{ip}"
		params = {
			:key=>@@api_key,
			:ip=>ip,
			:category => categories.join(",")
		}
		params[:comment] = comment.truncate(256) unless comment.nil?

		uri_str = "#{ABUSEIPDB_DOM}#{ABUSEIPDB_REPORT}?"+params.map{|k,v| "#{k}=#{CGI::escape(v.to_s)}"}.join('&')
		uri = URI(uri_str)

		# https://www.abuseipdb.com/report/json?key=xyz&ip=10.11.12.13&category=14%2C15
		# {"ip":"10.11.12.13","success":true}
		stream.puts uri_str
		#stream.puts uri.to_s
		result = {
			:success=>false
		}
		#puts uri.inspect
		begin
		Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https', :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
			request = Net::HTTP::Get.new uri.request_uri
			response = http.request request
			#puts response.inspect
			json=response.body
			if json.empty?
				result[:error]={
					"status"=>1,
					"code"=>1,
					"title"=>"empty response"
				}
			end
			begin
				resp=JSON.parse(json) #, :symbolize_names => true)
				case resp
				when Array
					if resp[0] && (resp[0].key?("status") || resp[0].key?("code"))
						#[
						#  {
						#    "id": "Too Many Requests",
						#    "links": {
						#      "about": "https://www.abuseipdb.com/api"
						#    },
						#    "status": "429",
						#    "code": "1050",
						#    "title": "The user has sent too many requests in a given amount of time.",
						#    "detail": "You have exceeded the rate limit for this service."
						#  }
						#]
						resp = resp[0]
						resp[:error] = "Received error"
					end
				when Hash
					# make sure response is an Array
				else
					resp = {
						:error => "Unknown resp class: #{resp.class}"
					}
					@@log.error resp[:error]
				end

				resp.each_pair { |key, val|
					next if val.nil?
					result[key.to_sym] = val
				}
			rescue => e
				@@log.error "Failed to parse json response: #{json}"
				@@log.error e.to_s
			end
		end
		if result[:error].nil? && result[:success]
			@@memoizer_data[:report][ip]=result

			save_memoizer(:report)
		end
		rescue Net::ReadTimeout => e
			result[:error]=e.message
		rescue => e
			result[:error]=e.message
		end
		result.nil? ? {:error => "empty result"} : result
	end

	def self.gethostaddress(hostname)
		ip = hostname
		begin
			ip = Resolv.getaddress(hostname)
		rescue
			# return the hostname on error
		end
		ip
	end

	def self.gethostname(ip)
		hostname = ip
		begin
			hostname = Resolv.getname(ip)
		rescue => e
			# return the ip address on error
		end
		hostname
	end

	def self.get_whitelisted_ips(whitelist, stream)
		wips={}
		return wips if whitelist.nil?

		stream.puts "Resolving whitelist: #{whitelist.inspect}"
		whitelist.each { |hostname|
			ip = hostname
			if ip.ipaddress?
				# it's an ip address, get the host name
				hostname = gethostname(ip)
			else
				# it's a hostname, get its ip address
				ip = gethostaddress(hostname)
			end
			wips[ip] = hostname
		}
		stream.puts "Resolved whitelist: #{wips.inspect}"
		return wips
	end

	def self.is_whitelisted(ip, stream, wips)
		return false if wips.nil?
		wips.each_pair { |wip, host|
			if ip.eql?(wip)
				stream.puts "IP #{ip} [#{host}] is whitelisted"
				return true
			end
		}
		return false
	end

	def self.check_entries(iplist, stream, opts)
		errors=0
		results={}
		iplist.each { |ip|
			next if is_whitelisted(ip, stream, opts[:wips])

			# limited to 60 checks per minute
			result = AbuseIPDB.memoized(ip, :check)
			if result.nil?
				result = AbuseIPDB.check(ip)
				sleep opts[:sleep_secs]
			end

			next if result.nil? || result.empty?

			unless result[:error].nil?
				@@log.error result[:error]
				errors += 1
				# just give up
				break if errors >= 10
				sleep opts[:sleep_secs]
			end

			results[ip]=result

		} unless $opts[:ipdb_apikey].nil?
		results
	end

end
