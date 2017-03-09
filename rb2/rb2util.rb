
require_relative File.join(File.dirname($0), "rb2conf")

class Rb2Util
	RB2_INIT = "rb2.init"

	# class variables
	@@log = Logger.new(STDERR)

	def self.init(opts)
		@@log = opts[:logger] if opts.key?(:logger)
	end

	def self.get_init(dest)
		@@log.die "Backup destination not found: #{dest}" unless File.exists?(dest)
		@@log.die "Backup destination is not a directory: #{dest}" unless File.directory?(dest)
		File.join(dest, RB2_INIT)
	end

	def self.is_initialized(rb2c)
		dest=rb2c.globals.dest
		init=get_init(dest)
		unless File.exists?(init)
			@@log.error "Backup destination is not initialized: #{dest}"
			return false
		end
		true
	end

	def self.init_backup_dest(rb2c)
		dest=rb2c.globals.dest
		raise Rb2Error, "Destination is not a directory: #{dest}" if File.exist?(dest) && !File.directory?(dest)
		create_backup_destination(dest)
		initialize_backup_destination(dest)
	rescue Rb2Error => e
		@@log.die "Failed to initialize backup dest=#{dest}: #{e.message}"
	rescue => e
		@@log.die "Failed to initialize backup dest=#{dest} unknown: #{e.to_s}"
	end

	def self.create_backup_destination(dest)
		return if File.directory?(dest)

		raise Rb2Error, "#{dest} already exists and is not a directory" if File.exists?(dest)

		@@log.info "Creating backup directory: #{dest}"
		# if a rubac directory exists, just create a symlink to it
		base=File.dirname(dest)
		rb2 =File.basename(dest)
		rubac=File.join(base, "rubac")
		if File.exists?(rubac)
			@@log.info "Linking backup directory #{dest} -> #{rubac}"
			FileUtils.chdir(base) {
				@@log.info FileUtils.ln_s "rubac", rb2, :verbose => true
			}
		else
			FileUtils.mkdir_p(dest)
		end
	rescue => e
		raise Rb2Error, "Failed to create backup destination #{dest} [#{e.to_s}]"
	end

	def self.initialize_backup_destination(dest)
		mask=File.umask(0066)
		init = get_init(dest)
		@@log.warn "Backup directory already initialized #{init}" if File.exist?(init)
		File.open(init, "w") { |fd|
			fd.puts "Backup directory initialized #{dest} [#{Time.now.utc.to_s}]"
		}
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
end

