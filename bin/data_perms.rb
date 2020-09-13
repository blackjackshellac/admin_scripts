#!/usr/bin/env ruby
#
# data_perms.rb
#

require 'logger'
require 'optparse'
require 'json'
require 'fileutils'
require 'etc'

ME=File.basename($0, ".rb")
MD=File.expand_path(File.dirname(File.realpath($0)))

class Logger
	def err(msg)
		self.error(msg)
	end

	def die(msg)
		self.error(msg)
		exit 1
	end
end

def set_logger(stream)
	log = Logger.new(stream)
	log.level = Logger::INFO
	log.datetime_format = "%Y-%m-%d %H:%M:%S"
	log.formatter = proc do |severity, datetime, progname, msg|
		"#{severity} #{datetime}: #{msg}\n"
	end
	log
end

$log = set_logger(STDERR)

class Hash
	def hkey(key)
		# try as-is
		return self[key] if self.key?(key)
		# try symbol key if it's not already a symbol
		unless key.class == Symbol
			key=key.to_sym
			return self[key] if self.key?(key)
		end
		# try string key
		key=key.to_s
		self[key]
	end
end

class PermsConfig
	attr_reader :basedir, :perms
	def initialize(h)
		@basedir=h.hkey(:basedir)
		aperms=h.hkey(:perms)
		@perms=[]
		aperms.each { |hperm|
			perm=Perms.from_h(hperm)
			@perms << perm
		}
		self.sort
	end

	def self.parse(json)
		h=JSON.parse(json, :symbolize_names => true)
		PermsConfig.new(h)
	end

	def self.load(dir, config)
		json=File.read(File.join(dir, config))
		PermsConfig.parse(json)
	end

	def sort
		@perms.sort! { |a,b|
			a.dir.length <=> b.dir.length
		}
	end

end

class Perms
	@@log = Logger.new(STDOUT)

	attr_reader :dir,:user,:grp,:fmod,:dmod,:uid,:gid
	def initialize(dir,user,grp,fmod,dmod)
		@dir=dir
		@user=user
		@grp=grp
		@fmod=fmod.to_i(8)
		@dmod=dmod.to_i(8)

		@uid=Etc.getpwnam(user).uid
		@gid=Etc.getgrnam(grp).gid
	end

	def to_h
		{
			:dir=>@dir,
			:user=>@user,
			:grp=>@grp,
			:fmod=>"0o%o" % @fmod,
			:dmod=>"0o%o" % @dmod
		}
	end

	def to_json(*a)
		to_h.to_json(*a)
	end

	def self.from_h(h)
		Perms.new(h.hkey(:dir), h.hkey(:user), h.hkey(:grp), h.hkey(:fmod), h.hkey(:dmod))
	end

	def to_s
		"%s> %s.%s [%d.%d] 0o%o 0o%o" % [ @dir, @user, @grp, @uid, @gid, @fmod, @dmod ]
	end

	def self.init(log)
		@@log = log
	end

	def self.list_opts(opts)
		opts={} if opts.nil?
		opts[:hidden]=false if opts[:hidden].nil?
		opts[:perms]=[] if opts[:perms].nil?
		opts[:stats]={} if opts[:stats].nil?
		opts
	end

	def self.list_dirs(dir, opts={:hidden=>false})
		opts=list_opts(opts)
		Dir.entries(".").select { |f| File.directory?(f) && !File.symlink?(f) && (opts[:hidden]||f[/^[.]/].nil?) }.map{ |f| File.absolute_path f }
	end

	def self.list_files(dir, opts={:hidden=>false})
		opts=list_opts(opts)
		Dir.entries(".").select { |f| File.file?(f) && !File.symlink?(f) && (opts[:hidden]||f[/^[.]/].nil?) }.map{ |f| File.absolute_path f }
	end

	def self.find_perm(dir, opts)
		opts=list_opts(opts)
		aperms=opts[:perms]
		raise "No directory permissions found" if aperms.empty?
		perm=nil
		aperms.each { |p|
			perm=p if dir.start_with?(p.dir)
		}
		perm=aperms[0] if perm.nil?
		perm
	end

	def self.compare_fix(name, stat, perm, fix=false, stats={})
		pmode=stat.directory? ? perm.dmod : perm.fmod
		smode=stat.mode & 07777

		usame = stat.uid == perm.uid
		gsame = stat.gid == perm.gid
		msame = smode == pmode

		return false if usame && gsame && msame

		# https://ruby-doc.org/stdlib-2.4.1/libdoc/fileutils/rdoc/FileUtils.html#method-c-chown
		# chown(user, group, list, noop: nil, verbose: nil)
		# chmod(mode, list, noop: nil, verbose: nil)

		user=nil
		grp=nil
		mode=nil

		umsg = ""
		unless usame
			umsg = "uid(got %d expected %d)" % [ stat.uid, perm.uid ]
			user = perm.user
		end

		gmsg = ""
		unless gsame
			gmsg = "gid(got %d expected %d)" % [ stat.gid, perm.gid ]
			grp = perm.grp
		end

		mmsg = ""
		unless msame
			mmsg = "mode(got 0o%o expected 0o%o)"  % [ smode, pmode ]
			mode = pmode
		end

		msg="%s %s %s" % [ umsg, gmsg, mmsg ]
		@@log.info "Diff detected: %s: %s" % [ name, msg ]

		if user || grp
			#FileUtils.chown user, grp
			@@log.info "FileUtils.chown %s, %s, %s, noop: %s" % [ user, grp, name, !fix ]
			FileUtils.chown user, grp, name, noop: !fix, verbose: true
		end

		if mode
			@@log.info "FileUtils.chmod 0%o, %s, noop: %s" % [ mode, name, !fix ]
			FileUtils.chmod mode, name, noop: !fix, verbose: true
		end

		stats[name]=msg if fix

		true
	end


	def self.fix_r(dir, opts={:hidden=>false})
		perm=find_perm(dir, opts)
		dstat=File.lstat(dir)
		Perms.compare_fix(dir, dstat, perm, opts[:fix], opts[:stats]) unless dir.eql?(opts[:basedir])
		Dir.chdir(dir) {
			@@log.debug "\nDirectory: #{dir} Perm: [#{perm}]"
			subdirs=Perms.list_dirs(dir)
			@@log.debug subdirs.inspect
			@@log.debug "Files"
			files=Perms.list_files(dir)
			files.each { |file|
				fstat=File.lstat(file)
				Perms.compare_fix(file, fstat, perm, opts[:fix], opts[:stats])
				@@log.debug " >> %s [%s.%s 0o%o]" % [ file, fstat.uid, fstat.gid, fstat.mode & 07777 ]
			}
			subdirs.each { |subdir|
				if File.symlink?(subdir)
					@@log.debug " >>> skipping symlink #{subdir}"
				else
					@@log.debug " >>> fix_r %s [%s.%s 0o%o]" % [ subdir, dstat.uid, dstat.gid, dstat.mode & 07777 ]
					Perms.fix_r(subdir, opts)
				end
			}
		}
	end
end

# foo_perms.json
# {
#    "basedir": "/data/foo",
#    "perms": [
#       {
#			"dir":"/data/foo",
#			"user": "john",
#			"grp": "fam",
#			"fmod": "0o660",
#			"dmod": "0o3770"
#       },
#       ....
#    ]
# }
$opts={
	:config=>nil,
	:config_dir=>__dir__,
	:fix=>false,
	:basedir=>nil,
	:perms=>nil,
	:stats => {
	}
}

optparser=OptionParser.new { |opts|
	opts.banner = "#{ME}.rb [options]\n"

	opts.on('-c', '--config JSON', String, "Permissions config json data") { |json|
		$opts[:config]=json
	}

	opts.on('-f', '--[no-]fix', "Default is to not fix permissions") { |fix|
		$opts[:fix]=fix
	}

	opts.on('-d', '--debug', "Enable debugging output") {
		$log.level = Logger::DEBUG
	}

	opts.on('-h', '--help', "Help") {
		$stdout.puts "#{ME}"
		$stdout.puts opts
		exit 0
	}
}
optparser.parse!

$log.die "Must specify config file" if $opts[:config].nil?

pconfig=PermsConfig.load($opts[:config_dir], $opts[:config])
$opts[:basedir]=pconfig.basedir
$opts[:perms]=pconfig.perms
$opts[:config]=pconfig

$log.debug JSON.pretty_generate($opts)

Perms.init($log)
Perms.fix_r($opts[:basedir], $opts)

$opts[:stats].each_pair { |file, msg|
	puts "%s: %s" % [ file, msg ]
}

# return non-zero if changes were made
exit $opts[:stats].empty? ? 0 : 1

