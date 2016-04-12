#
#
#

module Devices

  def self.run(cmd)
    	puts cmd
      IO.popen(cmd) do |fd|
        # or, if you have to do something with the output
        fd.each { |line|
          $stdout.puts line
          $stdout.flush
        }
      end
      # puts %x[#{cmd}]
  end

  def self.isLuks(dev)
  	Devices.run("cryptsetup isLuks #{dev}")
  	return ($?.exitstatus == 0)
  end

  def self.openLuks(dev, name)
  	raise "Device #{dev} is not a luks device" unless isLuks(dev)
  	mapper="/dev/mapper/#{name}"
  	unless File.exists?(mapper)
  		Devices.run("cryptsetup open --type luks #{dev} #{name}")
  		raise "Failed to unlock luks device #{name}" unless $?.exitstatus == 0
  	end
  	return mapper
  end

  def self.mountDev(dev, mp, options=nil)
  	options="" if options.nil?
    cmd="mount #{options} #{dev} #{mp}"
  	Devices.run(cmd)
  	raise "Failed to mount: '#{cmd}'" unless $?.exitstatus == 0
  end

  def self.runScripts(mp)
  	$opts[:scripts].each { |script|
  		run("#{script} #{mp}")
  		raise "Failed to run #{script} #{mp}" unless $?.exitstatus == 0
  	}
  end

  def self.found(dev)
    File.exists?(dev) && File.blockdev?(dev)
  end

end
