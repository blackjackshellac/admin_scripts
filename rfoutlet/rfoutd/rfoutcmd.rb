
require 'json'

class RFOutCmd

	attr_reader :name, :state, :when, :random
	def initialize(cmd)
		raise "Must specify a name for the outlet(s)" if cmd[:name].nil?
		raise "Must specify a on/off state for the named outlet(s)" if cmd[:state].nil?
		@name=cmd[:name]
		@state=cmd[:state]
		@when=cmd[:when]
		@random=cmd[:random]
	end

	def self.fromNameState(name, state)
		return RFOutCmd.new({:name=>name, :state=>state})
	end

	def self.fromJson(json)
		cmd=JSON.parse(json, :symbolize_names => true)
		return RFOutCmd.new(cmd)
	rescue => e
		puts "Failed to parse json: #{e.to_s}"
		nil
	end

	def to_json
		obj={}
		obj[:name]=@name
		obj[:state]=@state
		obj[:when]=@when unless @when.nil?
		obj[:random]=@random unless @random.nil?
		obj.to_json
	end
end
