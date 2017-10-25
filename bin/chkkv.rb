#!/usr/bin/env ruby
#
#

require 'time'

#newest=$(rpm -q kernel --last | head -1 | cut -f1 -d' ').$(uname -p)
#current=kernel-$(uname -r)

class CheckKernelVersion
	RE_KERNEL_STRING_SPLIT=/\s+/

	class << self
		attr_accessor :kernels, :platform, :latest, :current, :kernels_map
	end

	def self.kernel_time(kernel)
		bits=kernel.split(RE_KERNEL_STRING_SPLIT, 2)
		raise "Unexpected kernel string: #{kernel}" unless bits.length == 2
		[ bits[0],Time.parse(bits[1]) ]
	end

	def self.kernels_map
		# ensure that kernels list is initialized
		kernels
		unless defined? @@kernels_map
			@@kernels_map={}
			valid=@@kernels.length > 0
			@@kernels.each { |kernel|
				begin
					k,time=kernel_time(kernel)
					@@kernels_map[k]=time
				rescue => e
					valid=false
					puts e.to_s
				end
			}
			raise "kernel listing invalid" unless valid
		end
		@@kernels_map
	end

	def self.latest
		# set idx to 1 to change latest to an earlier kernel for testing
		idx=0
		unless defined? @@latest
			k,time=kernel_time(@@kernels[idx])
			@@latest={
				:kernel=>k,
				:time=>time
			}
		end
		@@latest
	end

	def self.current
		# ensure that kernels_map is initialized
		kernels_map
		unless defined? @@current
			kernel="kernel-#{%x/uname -r/.strip}"
			time=@@kernels_map[kernel]
			raise "Kernel from 'uname -r' not found in kernel map: #{kernel}" if time.nil?
			@@current={
				:kernel=>kernel,
				:time=>time
			}
		end
		@@current
	end

	# kernel-4.13.5-200.fc26.x86_64                 Wed 11 Oct 2017 02:00:36 AM EDT
	# kernel-4.13.4-200.fc26.x86_64                 Thu 05 Oct 2017 02:01:48 AM EDT
	# kernel-4.12.14-300.fc26.x86_64                Thu 28 Sep 2017 02:00:35 AM EDT
	def self.kernels
		unless defined? @@kernels
			@@kernels = %x/rpm -q kernel --last/.split(/\n/)
			kernels_map
			latest
			current
		end
		@@kernels
	rescue => e
		raise "Failed to list kernels: "+e.to_s
	end

	def self.platform
		@@platform=%x/uname -p/.strip
	rescue => e
		raise "Failed to grok uname platform string"
	end

	def self.is_current
		current
		latest
		@@current[:kernel].eql?(@@latest[:kernel]) && @@current[:time].eql?(@@latest[:time])
	end
	
	def self.as_string(kernel, time)
		"#{kernel} [#{time}]"
	end

	def self.map_as_string(entry)
		as_string(entry[:kernel], entry[:time])
	end

	def self.kernel_dump_test
		puts "      Number of kernels=#{kernels.length}"
		puts "             Kernel map="+kernels_map.inspect
		puts "         Running kernel="+map_as_string(@@current)
		puts "          Latest kernel="+map_as_string(@@latest)
		kernels_map.sort_by { |k,t| t }.reverse.each { |kernel,time|
			puts "                 Kernel="+as_string(kernel, time)
		}
		puts "        Test if current="+is_current.inspect
	end
end

#puts CheckKernelVersion.kernel_dump_test

puts "Running = #{CheckKernelVersion.map_as_string(CheckKernelVersion.current)}"
puts " Newest = #{CheckKernelVersion.map_as_string(CheckKernelVersion.latest)}"

exit CheckKernelVersion.is_current

### kernels=%x/rpm -q kernel --last/.split(/\n/)
### #kernel-3.10.0-514.6.1.el7.x86_64              Fri 20 Jan 2017 01:33:30 AM EST
### #kernel-3.10.0-514.2.2.el7.x86_64              Tue 13 Dec 2016 01:43:35 AM EST
### #kernel-3.10.0-327.36.3.el7.x86_64             Wed 26 Oct 2016 01:33:56 AM EDT
### #kernel-3.10.0-327.36.2.el7.x86_64             Wed 12 Oct 2016 01:34:35 AM EDT
### #kernel-3.10.0-327.28.3.el7.x86_64             Sat 20 Aug 2016 08:12:39 AM EDT
### 
### bits=kernels[0].split(/[\s]+/, 2)
### if bits.length != 2
### 	kernels.each { |k| puts k }
### 	raise "newest kernel not found in kernels output: #{kernels[0]}"
### end
### platform=%x/uname -p/.strip
### newest=bits[0]
### newest << ".#{platform}" if newest[/#{platform}$/].nil?
### #puts newest
### current = "kernel-#{%x/uname -r/.strip}"
### #puts current
### 
### #newest=$(rpm -q kernel --last | head -1 | cut -f1 -d' ').$(uname -p)
### #current=kernel-$(uname -r)
### #
### #info "Running = $current"
### #info "Newest  = $newest"
### #
### #if [ "$newest" != "$current" ]; then
### #	mail_log "New kernel available: $newest"
### #	exit 1
### #else
### #	info "Running kernel is newest"
### #fi
### 
### exit_status=newest.eql?(current) ? 0 : 1
### puts "Running = #{current}\n Newest = #{newest}"
### exit exit_status
### 
