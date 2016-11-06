
class WhoisData
	@@cat = {
		:netrange => %w/netrange inetnum/,
		:cidr     => %w/cidr route/,
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

		@@cat_keys.each { |cat|
			instance_variable_set("@#{cat}", nil)
			WhoisData.class_eval {
				attr_reader cat.to_sym
			}
		}
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
		cat = @wb.classify(line)
		@@log.debug "Classified cat = #{cat}/#{cat.class}: #{line}"

		if @@cat_keys.include?(cat)
			@data[cat] = line 
			# TODO check to see if @#{cat} is already set
			instance_variable_set("@#{cat}", line)
		end
	end

	def classify_addr(addr)
		WhoisData.whois(addr).each { |line|
			classify_line(line)
		}
	end

end

