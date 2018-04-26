
require 'uri'
require 'cgi'
require 'net/http'

class AbuseIPDB
	ABUSEIPDB_DOM="https://www.abuseipdb.com"
	ABUSEIPDB_CHECK="/check/%s/json"
	#ABUSEIPDB_URL="https://www.abuseipdb.com/%s/json?key=%s&days=%s"

	@@api_key=nil
	@@log = Logger.new(STDOUT)

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
		puts "#{resp.class}="+resp.inspect
		categories=[]
		if resp.class == Hash
			get_category(categories, resp)
		elsif resp.class == Array
			resp.each { |entry|
				get_category(categories, entry)
			}
		else
			@@log.error "Unknown response class: #{resp.class}"
		end
		categories.uniq.sort
	end

	def self.check(ip)
		return if @@api_key.nil?

		puts "AbuseIPDB: checking #{ip}"
		params = {
			:key=>@@api_key,
			:days=>30
		}
		uri_str = "#{ABUSEIPDB_DOM}#{ABUSEIPDB_CHECK % ip}?"+params.map{|k,v| "#{k}=#{CGI::escape(v.to_s)}"}.join('&')
		uri = URI(uri_str)

		puts uri.to_s
		puts uri.inspect

		categories = []
		Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https', :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
			request = Net::HTTP::Get.new uri.request_uri
			response = http.request request
			puts response.inspect
			json=response.body
			next if json.empty?
			resp=JSON.parse(json)
			categories.concat(get_categories(resp))
		end
		categories.uniq
	end
end
