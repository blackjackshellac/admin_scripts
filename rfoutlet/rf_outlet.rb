
require 'open3'

class RFOutlet
	ON  = "on"
	OFF = "off"

	@@codesend="/var/www/html/rfoutlet/codesend"
	@@rfsniffer="/var/www/html/rfoutlet/RFSniffer"

	attr_reader :label, :name, :code, :on, :off, :sched
	def initialize(label, h)
		@label = label
		@name = h[:name]
		@code = h[:code]
		@on   = h[:on]
		@off  = h[:off]
		@sched = h[:sched].nil? ? nil : Sched.new(h[:sched])
	end

	# {:outlet=>"o6",
	# 	:data=>{
	# 	:name=>"Stairway xmas lights",
	# 	:code=>"0304-2",
	# 	:on=>"5330371",
	# 	:off=>"5330380",
	# 	:sched=>{
	# 		:sunrise=>{:enabled=>true, :before=>"3600", :after=>"0", :duration=>"7200"},
	# 		:sunset=>{:enabled=>true, :before=>"1800", :after=>"300", :duration=>"21600"}
	# 	}
	# }
	# }
	#
	# @return true if the schedule has been updated
	def update(outlet, data)
		return false unless is_outlet(outlet)
		puts "#{@label}: update #{outlet} with #{data.inspect}"
		@name = data[:name] unless data[:name].nil?
		return false if data[:sched].nil?
		if @sched.nil?
			@sched = Sched.new(data[:sched])
		else
			@sched.update(data[:sched])
		end
		true
	end

	def eql?(other)
		return false if other.nil? || other.class != RFOutlet
		@label.eql?(other.label)
	end

	def is_outlet(outlet)
		outlet.to_s.eql?(@label.to_s)
	end

	def to_s
		"%s:[%s/%s](%s/%s)" % [ @label, @name, @code, @on, @off ]
	end

	def get_rfcode(state)
		(state.eql?(ON) ? @on : @off)
	end

	def self.get_state(state)
		state.eql?(ON) ? RFOutlet::ON : RFOutlet::OFF
	end

	def sendcode(rfcode)
		# return output
		cmd="#{@@codesend} #{rfcode}"
		out=""
		5.times { |i|
			out=%x[#{cmd}].strip
		}
		out
	rescue => e
		puts "Failed to execute [#{cmd}]: #{e.message}"
		exit 1
	end

	def turn(state)
		sendcode(get_rfcode(state))
	end

	def self.all_eof(files)
		files.find { |f| !f.eof }.nil?
	end

	def self.sniffer
		exit_status=0
		puts "\n"+"+"*50+"\n Use the remote to sniff some switch codes"
		Open3.popen3(@@rfsniffer) {|stdin, stdout, stderr, wait_thr|
			# or, if you have to do something with the output
			pid = wait_thr.pid

			fnout=stdout.fileno
			fnerr=stderr.fileno

			# https://gist.github.com/chrisn/7450808
			stdin.close_write
			begin
				files = [stdout, stderr]

				until all_eof(files) do
					puts "Select from #{files}"
					ready = IO.select(files)
					if ready
						readable = ready[0]
						# writable = ready[1]
						# exceptions = ready[2]

						readable.each { |f|
							#next if f.eof

							fileno = f.fileno
							line=""

							begin
								#data = f.read_nonblock(BLOCK_SIZE)
								#data = f.read_nonblock(32*1024)
								line=f.readline
								puts "line=#{line}"
								if fileno == fnout
									puts line
								elsif fileno == fnerr
									puts "Error: #{line}"
								end
								puts "fileno: #{fileno}, data: #{line}"
							rescue EOFError => e
								#puts "fileno: #{fileno} EOF"
								raise "Encountered unexpected EOF"
							rescue => e
								raise "Encountered unexpected exception: #{e.to_s}"
							end
						}
					end
				end
			rescue IOError => e
				puts "IOError: #{e}"
			end
			exit_status = wait_thr.value.exitstatus
			puts "exit_status = [#{exit_status}]"
		}
		exit_status
	end

end
