#!/usr/bin/env ruby
#

require 'sinatra'
# gem install sinatra-contrib
require 'sinatra/cookies'
require 'json'

# lazy auth
SECRET_TXT="/home/pi/bin/secret.txt"

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

get '/' do
	  #{"o1":"Upstairs hall","o2":"Living room bar","o3":"Living room","o4":"Blackboard hall","o5":"Den lamp","o6":"0304-3"}
	json=%x/rfoutlet.rb -J NAMES/
	names=JSON.parse(json, :symbolize_names=>true)

	erb :index, :locals => { :names=>names }
end

get '/on' do
	validate_secret

	outlet=request.env['HTTP_OUTLET']
	args= outlet.eql?("all") ? "-a" : "-#{outlet}"
	lines=%x/rfoutlet.rb #{args} -1/
	out=""
	lines.split(/\n/).each { |line| out+="#{line}<br/>\n" }
	out
end

get '/off' do
	validate_secret

	outlet=request.env['HTTP_OUTLET']
	args= outlet.eql?("all") ? "-a" : "-#{outlet}"
	lines=%x/rfoutlet.rb #{args} -0/
	out=""
	lines.split(/\n/).each { |line| out+="#{line}<br/>\n" }
	out
end

