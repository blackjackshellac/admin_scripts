#!/usr/bin/env ruby
#

require 'sinatra'
# gem install sinatra-contrib
require 'sinatra/cookies'
require 'json'

# lazy auth
SECRET_TXT="/home/pi/bin/secret.txt"

begin
	NAMES_CONFIG_JSON=%x/rfoutlet.rb -J NAMES/
	NAMES_CONFIG=JSON.parse(NAMES_CONFIG_JSON, :symbolize_names=>true)
rescue => e
	puts "Failed to load rfoutlet NAMES config data: #{e.message}"
	exit 1
end

set :port, 1966

def validate_secret
	#puts cookies.inspect
	secret=cookies[:secret]
	halt 401, "Invalid secret" if secret.empty?

	begin
		secret_txt=File.read(SECRET_TXT).strip
		halt 401, "Unauthorized secret=#{secret}" unless secret_txt.eql?(secret)
	rescue => e
		halt 401, "Failed to load secret from #{SECRET_TXT}: "+e.message
	end
end

def light_switch(args, state)
	args += (state ? " -1" : " -0")
	out=%x/rfoutlet.rb #{args}/
	puts out
	out.split(/\n/).map { |line| line+="<br>" }
end

get '/' do
	#{"o1":"Upstairs hall","o2":"Living room bar","o3":"Living room","o4":"Blackboard hall","o5":"Den lamp","o6":"0304-3"}
	erb :index, :locals => { :names=>NAMES_CONFIG }
end

get '/on' do
	validate_secret

	outlet = request.env['HTTP_OUTLET']
	halt 400, "No outlet specified in cookies" if outlet.nil? || outlet.empty?

	light_switch("-#{outlet}", true).to_json
end

get '/off' do
	validate_secret

	outlet=request.env['HTTP_OUTLET']
	halt 400, "No outlet specified in cookies" if outlet.nil? || outlet.empty?

	light_switch("-#{outlet}", false).to_json
end

