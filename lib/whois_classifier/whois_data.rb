
require 'netaddr'
require 'json'
require 'csv'

class WhoisData
	RE_IPV4_NETRANGE=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s*-\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
	RE_IPV4_CIDR=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}[\/]\d+)/
	#191.32/14
	RE_IPV4_CIDR_1=/(\d{1,3})([\/]\d+)/
	RE_IPV4_CIDR_2=/(\d{1,3}\.\d{1,3})([\/]\d+)/
	RE_IPV4_CIDR_3=/(\d{1,3}\.\d{1,3}\.\d{1,3})([\/]\d+)/

	FORMATS = {
		:text => "Text output",
		:inspect => "Debug inspect output",
		:csv  => "CSV output",
		:json => "JSON output",
		:pretty => "Prettified JSON output"
	}

	#network:IP-Network:50.116.64.0/18
	#network:IP-Network-Block:50.116.64.0 - 50.116.127.255

	@@cat = {
		:netrange => %w/netrange inetnum ip-network-block/,
		:cidr     => %w/cidr route ip-network netblock ip-network inetrev/,
		:country  => %w/country/,
		:regdate  => %w/regdate created/,
		:updated  => %w/updated last-modified changed/,
		:ignore   => %w//,
		:comment  => %w//
	}
	@@cat_keys = @@cat.keys
	@@ignore = %w/abuse-c abuse-mailbox address phone fax-no org organisation org-name org-type netname status origin remarks admin-c tech-c mnt-ref mnt-by/
	@@ignore.concat(%w/descr source role nic-hdl mnt-routes mnt-domains person at https via nethandle parent nettype originas customer ref custname city stateprov postalcode orgtechhandle orgtechname orgtechphone orgtechemail orgtechref orgabusehandle orgabusename orgabusephone orgabuseemail orgabuseref rtechhandle rtechname rtechphone rtechemail rtechref organization orgname orgid comment/)
	@@ignore.concat(%w/mnt-lower mnt-irt irt e-mail auth orgnochandle orgnocname orgnocphone orgnocemail orgnocref com network rnochandle rnocname rnocphone rnocemail rnocref rabusehandle rabusename rabusephone rabuseemail rabuseref notify net contact sponsoring-org netblock language aut-num owner ownerid responsible owner-c inetrev nserver nsstat nslastaa nic-hdl-br member-of/)
	@@ignore.concat(%w/class-name id auth-area network-name i updated-by street-address state postal-code country-code tech-contact handle/)
	@@ignore.concat(%w/organization;i tech-contact;i admin-contact;i id;i network-name;i parent;i org-contact;i abuse-contact;i noc-contact;i in-addr-server;i/)

	attr_reader :wb, :netrange, :cidr, :country, :regdate, :updated, :ignore, :line_cat
	def initialize(wb)
		@wb = wb

		@netrange = nil
		@cidr = nil
		@country = nil
		@regdate = nil
		@updated = nil
		@ignore = nil

		@line_cat = :ignore
	end

	def self.str2re(re)
		/#{re}/i
	rescue => e
		puts e.backtrace.join("\n")
		raise "Failed to create regular expression from string #{re}: "+e.to_s
	end

	def self.make_cat_re
		if @@cat_keys.empty?
			@@cat_re=str2re("^$")
		else
			re="^\\s*("
			@@cat_keys.each { |key|
				re+=Regexp.escape(key)+"|"
			}
			re+=")\\s+(.*)$"
			@@cat_re=str2re(re)
		end
	end

	def self.init(opts)
		@@log = opts[:logger]
		make_cat_re
	end

	def self.cat
		@@cat
	end

	def self.ignore
		@@ignore
	end

	def self.cat_keys
		@@cat_keys
	end

	def self.cat_re
		@@cat_re
	end

	def self.cat_from_line(line)
		return nil if line[@@cat_re].nil?
		return $1,$2
	end

	def self.is_ignore(cat)
		return @@ignore.include?(cat)
	end

	def self.get_category(cat)
		@@cat.each_pair { |kat, cats|
			return kat if kat.to_s.eql?(cat)
			return kat if cats.include?(cat)
		}
		nil
	end

	def self.whois(addr)
		#You can use encode for that. text.encode('UTF-8', :invalid => :replace, :undef => :replace)
		text = %x/whois #{addr}/.chars.select(&:valid_encoding?).join
		text.split(/\n/)
	end

	def getNetrange(line)
		return nil if line[RE_IPV4_NETRANGE].nil?
		netrange = [$1,$2]
		netrange
	end

	def getCidr(line)
		# route:          213.202.232.0/22
		cidr = []
		if !line[RE_IPV4_CIDR].nil?
			cidr << NetAddr::CIDR.create($1)
			@@log.debug "CIDR: #{cidr[0].to_s}"
		elsif !line[RE_IPV4_CIDR_1].nil?
			addr = "#{$1}.0.0.0#{$2}"
			cidr << NetAddr::CIDR.create(addr)
			@@log.debug "CIDR_1: #{cidr[0].to_s} from #{addr}"
		elsif !line[RE_IPV4_CIDR_2].nil?
			addr = "#{$1}.0.0#{$2}"
			cidr << NetAddr::CIDR.create(addr)
			@@log.debug "CIDR_2: #{cidr[0].to_s} from #{addr}"
		elsif !line[RE_IPV4_CIDR_3].nil?
			addr = "#{$1}.0#{$2}"
			cidr << NetAddr::CIDR.create(addr)
			@@log.debug "CIDR_3: #{cidr[0].to_s} from #{addr}"
		else
			@@log.error "CIDR not found in line: #{line}"
			cidr = nil
		end
		cidr
	end

	def getCidrFromNetrange
		lower = upper = nil
		if @netrange.class == Array
			lower = @netrange[0]
			upper = @netrange[1]
		elsif @netrange.class == String
			if @netrange[RE_IPV4_NETRANGE].nil?
				@@log.error "Netrange not found in :netrange: #{@netrange}"
				return nil
			end
			lower = $1
			upper = $2
		else
			raise "Invalid netrange value #{@netrange.class}/#{@netrange}"
		end

		@@log.debug "CIDR not found, look in :netrange #{@netrange}"
		# http://stackoverflow.com/questions/13406603/ip-range-to-cidr-in-ruby-rails
		@@log.debug "Create cidr from #{lower} - #{upper}"
		lower = NetAddr::CIDR.create(lower)
		upper = NetAddr::CIDR.create(upper)
		range = NetAddr.range(lower, upper, :Inclusive => true, :Objectify => true)
		@cidr = NetAddr.merge(range, :Objectify => true)
		@cidr.each_index { |i|
			cidr = @cidr[i]
			@@log.debug "CIDR #{i} #{cidr.to_s}"
		}
	end

	def getNetrangeFromCidr(cidr)
		nr = cidr.range(0, nil)
		return nr.first, nr.last
	end

	def classify_line(line)
		line.strip!
		cat = @wb.classify(line)
		cat = cat.to_sym

		@line_cat = cat

		@@log.debug "Classified cat = #{cat}/#{cat.class}: #{line}"
		return if :ignore.eql?(cat)

		@@log.debug "Look for #{cat} in #{@@cat_keys.inspect}"
		if @@cat_keys.include?(cat)
			cats = @@cat[cat]
			cats.each { |kat|
				re = /^\s*#{Regexp.escape(kat)}\s*:/i
				next if line[re].nil?
				line.sub!(re, "")
				line.strip!
				break
			}
			@@log.debug "Setting @#{cat} = #{line}"
			# TODO check to see if @#{cat} is already set
			case cat
			when :netrange
				# TODO look for RE_IPV4_* if range not found
				@netrange = getNetrange(line)
				@cidr = getCidr(line) if @netrange.nil?
			when :cidr
				@cidr = getCidr(line)
			when :country
				@country = line
			when :regdate
				@regdate = line
			when :updated
				@updated = line
			else
				instance_variable_set("@#{cat}", line)
			end
		end
	end

	def classify_cleanup
		if @cidr.nil?
			@cidr = getCidrFromNetrange unless @netrange.nil?
		elsif @netrange.nil?
			@netrange = getNetrangeFromCidr(@cidr[0])
		end
	end

	# RE_IPV4=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
	def classify_addr(addr)
		whois_text = ""
		WhoisData.whois(addr).each { |line|
			whois_text += "\n"+line
			classify_line(line)
		}
		classify_cleanup
		if @cidr.nil?
			if @netrange.nil?
				@@log.error "Netrange or CIDR not found"
			else
				@@log.error "CIDR not found"
			end
			@@log.error "whois #{addr}>>> "+whois_text+"\n<<<" if @cidr.nil?
		end
	end

	def to_hash
		nr = @netrange.nil? ? "<not found>" : ("%s - %s" % @netrange)
		h={
			:netrange => nr,
			:country  => @country,
			:regdate  => @regdate,
			:updated  => @updated
		}
		h[:cidr]=[]
		@cidr.each { |cidr|
			h[:cidr] << cidr
		} unless @cidr.nil?
		h
	end

	def to_format(format, opts={:stream=>$stdout, :headers=>false})
		res=""
		stream=opts[:stream]||$stdout
		case format
		when :text
			res=to_text
		when :inspect
			res=to_inspect
		when :json
			res=self.to_json
		when :pretty
			res=JSON.pretty_generate(to_hash)
		when :csv
			stream.puts to_csv(true) if opts[:headers]
			res=to_csv
		else
			raise "Unknown format: #{format}"
		end
		stream.puts res
	end

	def to_text
		h=to_hash
%/NetRange: #{h[:netrange]}
Country: #{h[:country]}
RegDate: #{h[:regdate]}
Updated: #{h[:updated]}
CIDR: #{h[:cidr].join(", ")}

/
	end

	def to_inspect
		to_hash.inspect
	end

	def to_json(*a)
		to_hash.to_json
	end

	def csv_headers
		%w/netrange country regdate updated cidr/.to_csv
	end

	def to_csv(headers=false)
		return csv_headers if headers
		h = to_hash
		[ h[:netrange], h[:country], h[:regdate], h[:updated], h[:cidr].join(" ") ].to_csv
	end
end

