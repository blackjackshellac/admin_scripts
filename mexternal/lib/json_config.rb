#
#
#

require 'json'

class JsonConfig < Hash
  def initialize
  end

  def to_json
    super.to_json
  end

  def from_json(json, clear=false)
    puts "json="+json
    h=JSON.parse(json, :symbolize_names=>true)
    self.clear if clear
    self.merge!(h)
    puts "self="+self.inspect
  end

  def from_file(file, clear=false)
    json=File.read(file)
    from_json(json, clear)
  end
end

unless ENV['JSON_CONFIG_TEST'].nil?
  jc = JsonConfig.new
  h={
    :doo=>"wop",
    :foo=>"bar",
    :baz=>"bam"
  }
  jc.from_json(h.to_json)
  puts "doo="+jc[:doo]
  jc.from_file("json_config_test.json", true)
end
