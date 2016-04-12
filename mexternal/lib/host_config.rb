#
#
#

require_relative 'json_config'

class HostConfig < JsonConfig
  HOSTCONFIG_DEFAULT_NAME="backup"

  def initialize(hc={})
    @hostname=%x/hostname -s/.strip
    self.clear
    self.merge!(hc)
  end

  def getHostConfig(host=nil)
    host=@hostname if host.nil?
    hc=self[host.to_sym]
    HostConfig.new(hc)
  end

  def getDefaultName()
    self[:default]||HOSTCONFIG_DEFAULT_NAME
  end

  def getNameConfig(name=nil)
    name=getDefaultName() if name.nil?
    nc=self[name.to_sym]
    nc[:name]=name
    HostConfig.new(nc)
  end

  def getName()
    raise "Key :name not found in HostConfig: "+self.inspect unless self.key?(:name)
    self[:name]
  end

  def getMountPoint()
    self[:mountpoint]||"/mnt/#{self[:name]}"
  end

  def getDevices()
    self[:devices]||[]
  end

  def getOptions()
    self[:options]||""
  end

  def getMapper()
    "/dev/mapper/"+getName()
  end

  def getScripts(scripts)
    self[:scripts]||scripts
  end
end

unless ENV['HOST_CONFIG_TEST'].nil?
  hc = HostConfig.new
  hc.from_file("host_config_test.json", true)
  hcc=hc.getHostConfig()
  puts hcc.inspect

  nc = hcc.getNameConfig()
  puts nc.getName()
  puts nc.getMountPoint()
  puts nc.getDevices()

end
