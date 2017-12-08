
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

	def to_s
		"%s/%s/%s/%s/%s" % [ @label, @name, @code, @on, @off ]
	end

	def get_rfcode(state)
		(state.eql?(ON) ? @on : @off)
	end

	def sendcode(rfcode)
		# return output
		%x[#{@@codesend} #{rfcode}].strip
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
