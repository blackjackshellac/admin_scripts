#!/usr/bin/env ruby
#
#

require 'fileutils'

me=$0
if File.symlink?(me)
	me=File.readlink($0)
	md=File.dirname($0)
	me=File.realpath(me)
end
ME=File.basename(me, ".rb")
MD=File.dirname(me)
LIB=File.realpath(File.join(MD, "..", "lib"))

HOSTNAME=%x/hostname -s/.strip
HOSTNAME_S=HOSTNAME.to_sym
CFG_PATH=File.join(MD, ME+".json")
HELP=File.join(MD, ME+".help")

require_relative File.join(LIB, "logger")
require_relative File.join(LIB, "o_parser")
require_relative File.join(MD, "rb2conf")

$log=Logger.set_logger(STDOUT, Logger::INFO)

TMP=File.join("/var/tmp", ME)
FileUtils.mkdir_p(TMP)
YMD=Time.now.strftime('%Y%m')

DEF_LOG_FORMAT="#{ME}.%Y-%m-%d.log"
LOG_FILE=Time.now.strftime(DEF_LOG_FORMAT)

UINDEX=Process.uid == 0 ? 0 : 1
LOG_DIR_ARRAY=[ File.join("/var/log", ME), TMP ]

DEF_DEST="/mnt/backup"
DEF_LOG_DIR=LOG_DIR_ARRAY[UINDEX]
DEF_LOG_PATH=File.join(DEF_LOG_DIR, LOG_FILE)
DEF_SMTP="localhost"
DEF_EMAIL=[]

$opts={
	:global => false,
	:clients => [],
	:address => [],
	:includes => [],
	:excludes => [],
	:nincrementals => nil,
	:dest => DEF_DEST,
	:logdir => DEF_LOG_DIR,
	:email => DEF_EMAIL,
	:smtp => DEF_SMTP,
	:logformat => DEF_LOG_FORMAT,
	:syslog => false,
	:action => :NADA,
	:daemonize => false,
	:logger => $log,
	:banner => "#{ME}.rb [options] process1 ...",
	:json=>ENV["RF_OUTLET_JSON"]||File.join(MD, "rfoutlet.json")
}

$opts = OParser.parse($opts, HELP) { |opts|
# -c, --client HOST       Client to backup (default is localhost), can specify multiple clients
# -a, --address HOST      Set the client host address (default is the client name)
# -i, --include PATH      Include path, comma separate multiple paths
# -x, --exclude PATH      Exclude path, comma separate multiple paths
# -o, --opts OPTS         Extra rsync options
# --delete            Delete any specified includes, excludes, opts
# --delete [client]   Delete the specified client configuration (does not purge the backups)
# -d, --dest DEST         Local destination path (eg., /mnt/backup)

	opts.on('-g', '--global', "Apply changes globally") {
		$opts[:global]=true
	}

	opts.on('-c', '--clients LIST', Array, "List of clients to act on") { |clients|
		$opts[:clients].concat(clients)
		$opts[:clients].uniq!
	}

	opts.on('-a', '--address HOSTS', Array, "Network address for specified client, should match client list") { |addrs|
		$opts[:address].concat(addrs)
		$opts[:address].uniq!
		$opts[:action]=:RECONFIG
	}

	opts.on('-i', '--include PATHS', Array, "Include path, comma separate multiple paths") { |paths|
		$opts[:includes].concat(paths)
		$opts[:includes].uniq!
		$opts[:action]=:RECONFIG
	}
	opts.on('-x', '--exclude PATHS', Array, "Exclude paths, comma separate multiple paths") { |paths|
		$opts[:excludes].concat(paths)
		$opts[:excludes].uniq!
		$opts[:action]=:RECONFIG
	}

	opts.on('-I', '--incrementals NUM', Integer, "Number of incremental backup directories") { |n|
		$opts[:nincrementals]=n
		$opts[:action]=:RECONFIG
	}

	opts.on('-d', "--dest PATH", String, "Backup path") { |path|
		$opts[:dest]=path
		$opts[:action]=:RECONFIG
	}

	opts.on('-L', "--logdir PATH", String, "Directory for logging, default #{DEF_LOG_DIR}") { |path|
		$opts[:logdir]=path
		$opts[:action]=:RECONFIG
	}

	opts.on('--log', "--log FORMAT", String, "Name format of log file, default #{DEF_LOG_FORMAT} - allow date/time formats") { |format|
		$opts[:logformat]=format
		$opts[:action]=:RECONFIG
	}

	opts.on('-m', '--mail EMAIL', Array, "Notification email address(es)") { |email|
		$opts[:email].concat(email)
		$opts[:email].uniq!
		$opts[:action]=:RECONFIG
	}

	opts.on('--syslog', "TODO use syslog for logging") {
		$opts[:syslog]=true
	}

#   -L, --logdir PATH       Directory for logging (root default is /var/log/rubac, otherwise TMP/rubac)
#       --log [NAME]        TODO Name of log file, (default is rubac.%Y-%m-%d.log)  - allow date/time formats
#   -m, --mail EMAIL        Notification email, comma separated list
#       --smtp SERVER       IP Address of smtp server (default is localhost)
#   -y, --syslog            TODO Use syslog for logging [??] [probably not since we have privlog]

	opts.on('--delete', "Delete specified address, includes, excludes, opts, etc") {
		$opts[:action]=:DELETE
	}

	opts.on('--delete-client', "Delete client config") {
		$opts[:action]=:DELETE_CLIENT
	}

	opts.on('-l', '--list [compact]', "List config") { |compact|
		$opts[:action]=compact.nil? ? :LIST : :LIST_COMPACT
	}

	opts.on('-b', '--bg', "Daemonize and run in background") {
		$opts[:daemonize]=true
	}
}

$log.debug $opts.inspect

Rb2Config.init($opts)
Rb2Globals.init($opts)

rb2c = Rb2Config.new
updated = false
case $opts[:action]
when :RECONFIG
	clen=$opts[:clients].length
	unless $opts[:address].empty?
		alen=$opts[:address].length
		# allow only 1 address per client
		raise "Client list length is different than address list length" if clen != alen
		rb2c.set_client_address($opts[:clients], $opts[:address])
	end

	unless $opts[:clients].empty?
		rb2c.set_client_includes($opts[:clients], $opts[:includes]) unless $opts[:includes].empty?
		rb2c.set_client_excludes($opts[:clients], $opts[:excludes]) unless $opts[:excludes].empty?
		rb2c.set_client_incrementals($opts[:clients], $opts[:nincrementals]) unless $opts[:nincrementals].nil?
	end
	rb2c.set_global_option($opts, :dest) unless $opts[:dest].nil?
	rb2c.set_global_option($opts, :logdir) unless $opts[:logdir].eql?(DEF_LOG_DIR)
	rb2c.set_global_option($opts, :logformat) unless $opts[:logformat].eql?(DEF_LOG_FORMAT)
	rb2c.set_global_option($opts, :email) unless $opts[:email].empty?
	rb2c.set_global_option($opts, :syslog) unless $opts[:syslog] == rb2c.globals.syslog

	updated=true

when :DELETE

	unless $opts[:clients].empty?
		rb2c.delete_client_address($opts[:clients], $opts[:address]) unless $opts[:address].empty?
		rb2c.delete_client_includes($opts[:clients], $opts[:includes]) unless $opts[:includes].empty?
		rb2c.delete_client_excludes($opts[:clients], $opts[:excludes]) unless $opts[:excludes].empty?
		updated=true
	end
	res=nil
	res||=rb2c.delete_global_option($opts, :dest) unless $opts[:dest].eql?(DEF_DEST)
	res||=rb2c.delete_global_option($opts, :logdir) unless $opts[:logdir].eql?(DEF_LOG_DIR)
	res||=rb2c.delete_global_option($opts, :logformat) unless $opts[:logformat].eql?(DEF_LOG_FORMAT)
	res||=rb2c.delete_global_option($opts, :email) unless $opts[:email].empty?
	res||=rb2c.delete_global_option($opts, :syslog) unless $opts[:syslog] == rb2c.globals.syslog
	updated=!res.nil?

when :DELETE_CLIENT

	$log.die "Must specify client to delete" if $opts[:clients].empty?
	$log.debug "Deleting clients: #{$opts[:clients].inspect}"
	rb2c.delete_clients($opts[:clients])

	updated=true

when :LIST
	rb2c.list(false)
when :LIST_COMPACT
	rb2c.list(true)
when :NADA
	$log.die "No action options specified"
else
	raise "Shouldn't get here"
end

rb2c.save_config if updated #(Rb2Config::CONF_ROOT)
