#
# A HostConfig object can hold a collection of HostConfigs, a single HostConfig or a single name within a HostConfig
#

require_relative 'json_config'

class HostConfig < JsonConfig
  HOSTCONFIG_DEFAULT_NAME="backup"
  HOSTCONFIG_DEFAULT_OPTS={
    :hc=>{},
    :logger=>nil
  }

  def initialize(opts=HOSTCONFIG_DEFAULT_OPTS)
    opts[:hc] = {} if opts[:hc].nil?
    @opts = opts
    @log = @opts[:logger]
    @hostname=%x/hostname -s/.strip
    self.clear
    self.merge!(opts[:hc].nil? ? {} : opts[:hc])
  end

  # get config for this host
  def getHostConfig(host=nil)
    host=@hostname if host.nil?
    hc=self[host.to_sym]
    raise "HostConfig not found for #{host}" if hc.nil?
    HostConfig.new(:hc=>hc, :logger=>@log)
  end

  def filterName(name=nil)
    return if name.nil?
    self.select! { |k,v| k == name.to_sym }
    self
  end

  def getDefaultName()
    self[:default]||HOSTCONFIG_DEFAULT_NAME
  end

  # get name config hash from host config retrieved with getHostConfig
  # "host"=>{"foo"=>{}}
  def getNameConfig(name=nil)
    name=getDefaultName() if name.nil?
    nc=self[name.to_sym]
    raise "HostConfig name not found: "+name if nc.nil?
    # record name in hosts name config
    nc[:name]=name
    HostConfig.new(:hc=>nc, :logger=>@log)
  end

  def getName()
    raise "Key symbol :name not found in HostConfig, did you call getNameConfig()?: "+self.inspect unless self.key?(:name)
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

  def addDevice(host, name, device)
    host=@hostname if host.nil?
    name=getDefaultName() if name.nil?
    hcc = self[host.to_sym]||{:default=>name}
    nc = hcc[name.to_sym]||{:name=>name}
    devices = nc[:devices]||[]
    devices << device
    # record changes in self
    nc[:devices]=devices
    hcc[name.to_sym]=nc
    self[host.to_sym]=hcc
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
