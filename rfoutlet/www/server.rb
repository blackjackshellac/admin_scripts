#!/usr/bin/env ruby
#

require 'sinatra'
# gem install sinatra-contrib
require 'sinatra/cookies'
require 'json'

me=$0
if File.symlink?(me)
	me=File.readlink($0)
	md=File.dirname($0)
	me=File.realpath(me)
end
ME=File.basename(me, ".rb")
MD=File.dirname(me)
LIB=File.realpath(File.join(MD, "../..", "lib"))

require_relative File.join(LIB, "logger")
require_relative File.join('..', "rfoutletconfig")
require_relative File.join('..', "rf_outlet")

$log=Logger.set_logger(STDOUT, Logger::INFO)

CFG="/home/pi/bin/rfoutlet.json"

# lazy auth
SECRET_TXT="/home/pi/bin/secret.txt"

begin
	RFOutletConfig.init(:logger=>$log)
	$log.info "Loading RF config #{CFG}"
	rfoc=RFOutletConfig.new(CFG)
rescue => e
	puts "Failed to load RF outlet config: #{CFG}"
	puts e.message
	exit 1
end

begin
	NAMES_CONFIG_JSON=rfoc.print_item(:NAMES) #%x/rfoutlet.rb -J NAMES/
	NAMES_CONFIG=JSON.parse(NAMES_CONFIG_JSON, :symbolize_names=>true)
	puts NAMES_CONFIG_JSON
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

def string2array(out, suffix)
	out.split(/\n/).map { |line| line+="<br>" }
end

def light_switch(args, state)
	args += (state ? " -1" : " -0")
	%x/rfoutlet.rb #{args}/
end

get '/' do
	#{"o1":"Upstairs hall","o2":"Living room bar","o3":"Living room","o4":"Blackboard hall","o5":"Den lamp","o6":"0304-3"}
	erb :index, :locals => { :names=>NAMES_CONFIG }
end

get '/on' do
	validate_secret

	outlet = request.env['HTTP_OUTLET']
	halt 400, "No outlet specified in cookies" if outlet.nil? || outlet.empty?

	state=RFOutlet::ON

	labels = outlet.eql?("a") ? rfoc.outlets.keys : [ outlet ]
	out=""
	labels.each { |label|
		rfo=rfoc.set_outlet(label)
		out += "Turning #{state.downcase} #{rfo.name}\n"
		out += "%s\n" % rfo.turn(state)
	}
	string2array(out, "<br>")
end

get '/off' do
	validate_secret

	outlet=request.env['HTTP_OUTLET']
	halt 400, "No outlet specified in cookies" if outlet.nil? || outlet.empty?

	state=RFOutlet::OFF

	labels = outlet.eql?("a") ? rfoc.outlets.keys : [ outlet ]
	out=""
	labels.each { |label|
		rfo=rfoc.set_outlet(label)
		out += "Turning #{state.downcase} #{rfo.name}\n"
		out += "%s\n" % rfo.turn(state)
	}
	string2array(out, "<br>")
end

