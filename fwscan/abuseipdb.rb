
require 'uri'
require 'cgi'
require 'net/http'
require 'tempfile'

class AbuseIPDB
	ABUSEIPDB_DOM="https://www.abuseipdb.com"
	ABUSEIPDB_CHECK="/check/%s/json"
	#ABUSEIPDB_URL="https://www.abuseipdb.com/%s/json?key=%s&days=%s"

	@@api_key=nil
	@@log = Logger.new(STDOUT)

	@@memoizer = {}

	def initialize
	end

	def self.init(opts)
		@@log = opts[:logger] unless opts[:logger].nil?
		@@api_key = opts[:ipdb_apikey] unless opts[:ipdb_apikey].nil?
		@@log.info "API KEY=#{@@api_key}"
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

	def self.check(ip)
		return { :error=> "API key not set" } if @@api_key.nil?

		if @@memoizer.key?(ip)
			@@log.info "Address is already scanned: #{ip}"
			return @@memoizer[ip]
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
			:error=>nil
		}
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
				resp=JSON.parse(json)
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
		@@memoizer[ip]=result unless result[:error].nil?
		result
	end

end
