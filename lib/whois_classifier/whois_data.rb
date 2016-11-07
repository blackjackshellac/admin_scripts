
require 'netaddr'
require 'json'

class WhoisData
	RE_IPV4_NETRANGE=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s*-\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
	RE_IPV4_CIDR=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}[\/]\d+)/
	#191.32/14
	RE_IPV4_CIDR_1=/(\d{1,3})([\/]\d+)/
	RE_IPV4_CIDR_2=/(\d{1,3}\.\d{1,3})([\/]\d+)/
	RE_IPV4_CIDR_3=/(\d{1,3}\.\d{1,3}\.\d{1,3})([\/]\d+)/

	#network:IP-Network:50.116.64.0/18
	#network:IP-Network-Block:50.116.64.0 - 50.116.127.255

	@@cat = {
		:netrange => %w/netrange inetnum ip-network-block/,
		:cidr     => %w/cidr route ip-network netblock ip-network inetrev/,
		:country  => %w/country/,
		:regdate  => %w/regdate created/,
		:updated  => %w/updated last-modified changed/,
		:ignore   => %w//
	}
	@@cat_keys = @@cat.keys
	@@ignore = %w/abuse-c abuse-mailbox address phone fax-no org organisation org-name org-type netname status origin remarks admin-c tech-c mnt-ref mnt-by/
	@@ignore.concat(%w/descr source role nic-hdl mnt-routes mnt-domains person at https via nethandle parent nettype originas customer ref custname city stateprov postalcode orgtechhandle orgtechname orgtechphone orgtechemail orgtechref orgabusehandle orgabusename orgabusephone orgabuseemail orgabuseref rtechhandle rtechname rtechphone rtechemail rtechref organization orgname orgid comment/)
	@@ignore.concat(%w/mnt-lower mnt-irt irt e-mail auth orgnochandle orgnocname orgnocphone orgnocemail orgnocref com network rnochandle rnocname rnocphone rnocemail rnocref rabusehandle rabusename rabusephone rabuseemail rabuseref notify net contact sponsoring-org netblock language aut-num owner ownerid responsible owner-c inetrev nserver nsstat nslastaa nic-hdl-br member-of/)

	attr_reader :wb, :netrange, :cidr, :country, :regdate, :updated, :ignore
	def initialize(wb)
		@wb = wb

		@netrange = nil
		@cidr = nil
		@country = nil
		@regdate = nil
		@updated = nil
		@ignore = nil
	end

	def self.init(opts)
		@@log = opts[:logger]
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

	def self.is_ignore(cat)
		return @@ignore.include?(cat)
	end

	def self.get_category(cat)
		@@cat.each_pair { |kat, cats|
			return kat if cats.include?(cat)
		}
		nil
	end

	def self.whois(addr)
		#You can use encode for that. text.encode('UTF-8', :invalid => :replace, :undef => :replace)
		text = %x/whois #{addr}/.chars.select(&:valid_encoding?).join
		text.split(/\n/)
	end

	def classify_line(line)
		line.strip!
		cat = @wb.classify(line)
		cat = cat.to_sym

		return if :ignore.eql?(cat)

		@@log.debug "Classified cat = #{cat}/#{cat.class}: #{line}"

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
				@netrange = line
			when :cidr
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
				@cidr = cidr
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

	# RE_IPV4=/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
	def classify_addr(addr)
		whois_text = ""
		WhoisData.whois(addr).each { |line|
			whois_text += "\n"+line
			classify_line(line)
		}
		if @cidr.nil?
			if @netrange.nil?
				@@log.error "Netrange or CIDR not found"
			elsif @netrange[RE_IPV4_NETRANGE].nil?
				@@log.error "Netrange not found in :netrange: #{@netrange}"
			else
				@@log.debug "CIDR not found, look in :netrange #{@netrange}"
				# http://stackoverflow.com/questions/13406603/ip-range-to-cidr-in-ruby-rails
				lower = $1
				upper = $2
				@@log.debug "Create cidr from #{lower} - #{upper}"
				lower = NetAddr::CIDR.create($1)
				upper = NetAddr::CIDR.create($2)
				range = NetAddr.range(lower, upper, :Inclusive => true, :Objectify => true)
				@cidr = NetAddr.merge(range, :Objectify => true)
				@cidr.each_index { |i|
					cidr = @cidr[i]
					@@log.debug "CIDR #{i} #{cidr.to_s}"
				}
			end
			@@log.error "whois #{addr}>>> "+whois_text+"\n<<<" if @cidr.nil?
		end
	end

	def to_json(*a)
		h={
			:netrange => @netrange,
			:country  => @country,
			:regdate  => @regdate,
			:updated  => @updated
		}
		h[:cidr]=[]
		@cidr.each { |cidr|
			h[:cidr] << cidr
		}
		h.to_json
	end

end

