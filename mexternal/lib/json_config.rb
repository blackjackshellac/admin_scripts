#
#
#

require 'json'

class JsonConfig < Hash
  def initialize
  end

  def pretty_generate()
    JSON.pretty_generate(self)
  end

  def from_json(json, clear=false)
    self.clear if clear
    self.merge!(JSON.parse(json, :symbolize_names=>true))
  end

  def from_file(file, clear=false)
    json=File.read(file)
    from_json(json, clear)
  end

  def print(out=$stdout)
    out.puts pretty_generate()
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
