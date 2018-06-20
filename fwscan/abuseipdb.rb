
require 'uri'
require 'cgi'
require 'net/http'
require 'tempfile'
require 'json'
require 'fileutils'

class String
  def truncate(max)
	 length > max ? "#{self[0...max]}..." : self
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

	@@memoizer_check = nil
	@@memoizer_report = nil
	@@memoizer_check_data = {}
	@@memoizer_report_data = {}

	def initialize
	end

	def self.load_memoizer
		return if @@memoizer_check.nil? || !File.exists?(@@memoizer_check)

		json = File.read(@@memoizer_check)
		memoizer = JSON.parse(json, :symbolize_names => true)
		now = Time.now.to_i
		# check them once per day
		timeout = 86400
		puts "before "+memoizer.count.to_s
		memoizer = memoizer.delete_if { |ip, result|
			age=now-result[:time]
			delete=(age > timeout)
			action=delete ? "deleting" : "keeping"
			puts "#{action} ip=#{ip} time=#{result[:time]} now=#{now} age=#{age}"
			delete
		}
		# convert hash key symbols to strings
		memoizer.each_pair { |ip,result|
			@@memoizer_check_data[ip.to_s]=result
		}
		puts "after "+@@memoizer_check_data.count.to_s
	end

	#def self.save_memoizer
	#	return if @@memoizer_check.nil?
	#	puts " >> saving "+@@memoizer_check
	#	File.open(@@memoizer_check, "w") { |fd|
	#		fd.puts JSON.pretty_generate(@@memoizer_check_data)
	#	}
	#end

	# type is :check or :report
	def self.save_memoizer(type)
		file=self.class_variable_get("@@memoizer_#{type}")
		data=self.class_variable_get("@@memoizer_#{type}_data")
		return if file.nil?
		puts " >> saving "+file
		File.open(file, "w") { |fd|
			fd.puts JSON.pretty_generate(data)
		}
	end

	def self.init(opts)
		@@log = opts[:logger] unless opts[:logger].nil?
		@@api_key = opts[:ipdb_apikey] unless opts[:ipdb_apikey].nil?
		@@log.info "API KEY=#{@@api_key}"

		username=ENV['LOGNAME']||ENV['USERNAME']||ENV['USER']
		@@memoizer_check = "%s/abuseipdb_store.json" % (username.nil? ? "/var/tmp" : "/var/tmp/#{username}")
		dirname = File.dirname(@@memoizer_check)
		FileUtils.mkdir_p dirname
		@@memoizer_report = "#{dirname}/abuseipdb_report.json"

		load_memoizer
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
		if result[:error].nil?
			count=result[:raw].count
			fwlac = (fwla.nil? || fwla.empty?) ? 0 : fwla.count
			stream.puts "%s%15s (%d) - [%d] %s (%s) [%s]" % [ prefix, result[:ip], fwlac, count, result[:isoCode], result[:country], result[:categories].join(",") ] if count > 0 || fwlac  > 0
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

	def self.memoized(ip)
		@@memoizer_check_data[ip]
	end

	def self.check(ip)
		return { :error=> "API key not set" } if @@api_key.nil?

		if @@memoizer_check_data.key?(ip)
			@@log.info "Address is already scanned: #{ip}"
			return @@memoizer_check_data[ip]
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
			:time=>Time.now.to_i
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
				end

			rescue => e
				@@log.error "Failed to parse json response: #{json}"
				@@log.error e.to_s
			end
		end
		if result[:error].nil? && !result[:raw].empty?
			@@memoizer_check_data[ip]=result

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

		if @@memoizer_report_data.key?(ip)
			@@log.info "Address is already scanned: #{ip}"
			return @@memoizer_report_data[ip]
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
		result = {}
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
		if result[:error].nil?
			@@memoizer_report_data[ip]=result

			save_memoizer(:report)
		end
		rescue Net::ReadTimeout => e
			result[:error]=e.message
		rescue => e
			result[:error]=e.message
		end
		result.nil? ? {:error => "empty result"} : result
	end

	def self.check_entries(iplist, opts)
		errors=0
		results={}
		iplist.each { |ip|

			# limited to 60 checks per minute
			result = AbuseIPDB.memoized(ip)
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
