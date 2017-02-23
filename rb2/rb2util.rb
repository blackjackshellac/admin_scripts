
require_relative File.join(File.dirname($0), "rb2conf")

class Rb2Util
	# class variables
	@@log = Logger.new(STDERR)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.init_backup_dest(rb2c)
		dest=rb2c.get_global_option(:dest)
		raise Rb2Error, "Destination is not a directory: #{dest}" if File.exist?(dest) && !File.directory?(dest)
		create_backup_destination(dest)
		initialize_backup_destination(dest)
	rescue Rb2Error => e
		@@log.die "Failed to initialize backup dest=#{dest}: #{e.message}"
	rescue => e
		@@log.die "Failed to initialize backup dest=#{dest} unknown: #{e.to_s}"
	end

	def self.create_backup_destination(dest)
		FileUtils.mkdir_p(dest)
	rescue => e
		raise Rb2Error, "Failed to create backup destination #{dest} [#{e.to_s}]"
	end

	def self.initialize_backup_destination(dest)
		mask=File.umask(0066)
		init = File.join(dest, "rb2.init")
		raise Errno::EEXIST, "file #{init} already exists" if File.exist?(init)
		FileUtils.touch(init)
		FileUtils.chmod(0600, init)
	rescue Errno::EACCES => e
		raise Rb2Error, "access denied, initializing destination #{dest}"
	rescue Errno::EEXIST => e
		@@log.warn "backup destination #{dest} is already initialized: #{e.message}"
	rescue => e
		raise Rb2Error, "Failed initializing destination #{dest}: #{e.to_s}"
	ensure
		File.umask(mask)
	end
	true
end

