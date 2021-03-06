#!/usr/bin/env ruby
#

require 'sinatra/base'
# gem install sinatra-contrib
require 'sinatra/cookies'
require 'json'
require 'thread'

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
require_relative File.join('..', "sched")

$log=Logger.set_logger(STDOUT, Logger::INFO)

CFG=File.expand_path("~/bin/rfoutlet.json")

# lazy auth
SECRET_TXT=File.expand_path("~/bin/secret.txt")

RFOutletConfig.init(:logger=>$log)
Sched.init(:logger=>$log)

def loadRFOutletConfig(cfg)
	begin
		$log.info "Loading RF config #{cfg}"
		RFOutletConfig.new(cfg)
	rescue => e
		$log.error "Failed to load RF outlet config: #{cfg}"
		$log.die e.message
	end
end

$rfoc = loadRFOutletConfig(CFG)

$sched_queue = SchedQueue.new
$sched_thread = Sched.create_thread($sched_queue, $rfoc)

$rfoc.fillSchedQueue($sched_queue)

$sched_queue.slump

Signal.trap("HUP") do
	puts "Reloading queue #{$$}"
	$rfoc.reloadQueue(true)
end

class RFOutletServer < Sinatra::Base
	helpers Sinatra::Cookies

	set :port, 1966
	set :traps, false

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

	# append the suffix to each line in array out, returns the array of altered lines
	#
	# @param out - array of lines to alter
	# @param suffix - suffix to append to each line
	# @returns array of lines with suffix appended
	def append2lines(out, suffix)
		out.split(/\n/).map { |line| line+=suffix }
	end

	def light_switch(args, state)
		args += (state ? " -1" : " -0")
		%x/rfoutlet.rb #{args}/
	end

	before '/*' do
		path=request.path_info
		$log.info "path=.#{path}."
		unless path.eql?('/')
			$log.info "Validate secret for #{path}"
			validate_secret
		end
	end

	get '/' do
		#{"o1":"Upstairs hall","o2":"Living room bar","o3":"Living room","o4":"Blackboard hall","o5":"Den lamp","o6":"0304-3"}
		erb :index, :locals => { :names=>$rfoc.hash_config(:name) }
	end

	get '/on' do
		outlet = request.env['HTTP_OUTLET']
		halt 400, "No outlet specified in headers" if outlet.nil? || outlet.empty?

		state=RFOutlet::ON

		labels = outlet.eql?("a") ? $rfoc.outlets.keys : [ outlet ]
		out=""
		labels.each { |label|
			rfo=$rfoc.set_outlet(label)
			out += "Turning #{state.downcase} #{rfo.name}\n"
			out += "%s\n" % rfo.turn(state)
		}
		append2lines(out, "<br>")
	end

	get '/off' do
		outlet=request.env['HTTP_OUTLET']
		halt 400, "No outlet specified in headers" if outlet.nil? || outlet.empty?

		state=RFOutlet::OFF

		labels = outlet.eql?("a") ? $rfoc.outlets.keys : [ outlet ]
		out=""
		labels.each { |label|
			rfo=$rfoc.set_outlet(label)
			out += "Turning #{state.downcase} #{rfo.name}\n"
			out += "%s\n" % rfo.turn(state)
		}
		append2lines(out, "<br>")
	end

	get '/outlet' do
		outlet = request.env['HTTP_OUTLET']
		halt 400, "No outlet specified in headers" if outlet.nil? || outlet.empty?

		oc=$rfoc.outlet_config_json(outlet)
		halt 401, "Outlet not found #{outlet}" if oc.nil?
		oc
	end

	post '/outlet' do
		oc=JSON.parse(request.body.read, :symbolize_names=>true)
		outlet=oc[:outlet]
		data=oc[:data]
		$rfoc.update_outlet_config(outlet.to_sym, data)
		$rfoc.save_config
		$sched_queue.update_entry(outlet.to_s, data)
		$rfoc.fillSchedQueue($sched_queue)
		$sched_queue.slump
		$log.info "post outlet: "+oc.inspect
	end
end

$log.info "Running server (pid=#{$$})"
RFOutletServer.run!
