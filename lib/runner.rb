
require 'open3'
require 'logger'

module Runner

	DEF_OPTS={
		:dryrun=>false,
		:trim => false,
		:strip => false,
		:fail => true,
		:echo => true,
		:errmsg => "Command failed to run",
		:lines => [],
		:out => $stdout,
		:log => nil
	}

	@@log = Logger.new(STDERR)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.gov(opts, key)
		return opts.key?(key) ? opts[key] : DEF_OPTS[key]
	end

	def self.all_eof(files)
		files.find { |f| !f.eof }.nil?
	end

	def self.run3!(cmd, opts={})
		@@log.debug "#{Dir.pwd}/ $ #{cmd}"
		return 0 if gov(opts, :dryrun)

		exit_status = 0

		# if :lines option is array, record output to lines array
		lines = gov(opts, :lines)
		strip = gov(opts, :strip)
		out = gov(opts, :out)
		log = gov(opts, :log)

		Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|

			# or, if you have to do something with the output
			pid = wait_thr.pid

			fnout=stdout.fileno
			fnerr=stderr.fileno

			puts "fnout=#{fnout} fnerr=#{fnerr}"

			# https://gist.github.com/chrisn/7450808
			stdin.close_write
			begin
				files = [stdout, stderr]

				until all_eof(files) do
					ready = IO.select(files)
					if ready
						readable = ready[0]
						# writable = ready[1]
						# exceptions = ready[2]

						readable.each { |f|
							next if f.eof

							fileno = f.fileno

							begin
								#data = f.read_nonblock(BLOCK_SIZE)
								#data = f.read_nonblock(32*1024)
								data = f.readline
								puts "fileno: #{fileno}, data: #{data}"
							rescue EOFError => e
								puts "fileno: #{fileno} EOF"
							end
						}
					end

			#		if exit_status != 0
			#			stderr.each { |line|
			#				line.strip! if strip
			#				lines.push(line) unless lines.nil?
			#				unless out.nil?
			#					out.puts line
			#					out.flush
			#				end
			#				unless log.nil?
			#					log.error(line)
			#					log.flush
			#				end
			#			}
			#			return exit_status
			#		end
			#		stdout.each { |line|
			#			line.strip! if strip
			#			lines.push(line) unless lines.nil?
			#			if gov(opts, :echo)
			#				unless out.nil?
			#					out.puts line
			#					out.flush
			#				end
			#				unless log.nil?
			#					log.info(line)
			#					log.flush
			#				end
			#			end
			#		}
				end
			rescue IOError => e
				puts "IOError: #{e}"
			end
			exit_status = wait_thr.value.exitstatus
			puts "exit_status = [#{exit_status}]"
		end

		return exit_status

	end

	def self.run3(cmd, opts={})
		@@log.debug "#{Dir.pwd}/ $ #{cmd}"
		return 0 if gov(opts, :dryrun)

		# if :lines option is array, record output to lines array
		lines = gov(opts, :lines)
		strip = gov(opts, :strip)
		out = gov(opts, :out)
		log = gov(opts, :log)

		Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
			# or, if you have to do something with the output
			pid = wait_thr.pid
			exit_status = wait_thr.value
			if exit_status != 0
				stderr.each { |line|
					line.strip! if strip
					lines.push(line) unless lines.nil?
					unless out.nil?
						out.puts line
						out.flush
					end
					unless log.nil?
						log.error(line)
						log.flush
					end
				}
				return exit_status
			end
			stdout.each { |line|
				line.strip! if strip
				lines.push(line) unless lines.nil?
				if gov(opts, :echo)
					unless out.nil?
						out.puts line
						out.flush
					end
					unless log.nil?
						log.info(line)
						log.flush
					end
				end
			}
			return 0
		end
	end

	def self.run(cmd, opts={})
		err_msg=gov(opts, :errmsg)
		return "" if gov(opts, :dryrun)
		out=%x/#{cmd} 2>&1/
		if $?.exitstatus != 0
			f=gov(opts, :fail)
			if f == true
				@@log.error out
				@@log.die err_msg
			end
			out=""
		end
		return gov(opts, :trim) ? out.strip! : out
	end

end 
