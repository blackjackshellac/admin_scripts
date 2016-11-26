
require 'open3'
require 'logger'

module Runner

	DEF_OPTS={
		:dryrun=>false,
		:trim => false,
		:fail => true,
		:echo => true,
		:errmsg => "Command failed to run",
		:lines => []
	}

	@@log = Logger.new(STDERR)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.gov(opts, key)
		return opts.key?(key) ? opts[key] : DEF_OPTS[key]
	end

	def self.run3(cmd, opts={})
		@@log.debug "#{Dir.pwd}/ $ #{cmd}"
		unless gov(opts, :dryrun)
			lines = gov(opts, :lines)
			Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
				# or, if you have to do something with the output
				pid = wait_thr.pid
				exit_status = wait_thr.value
				if exit_status != 0
					stderr.each { |line|
						$stdout.puts line
						$stdout.flush
					}
					return exit_status
				end
				stdout.each { |line|
					if gov(opts, :echo)
						$stdout.puts line
						$stdout.flush
					end
					lines.push(line) unless lines.nil?
				}
			end
		end
		return 0
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
