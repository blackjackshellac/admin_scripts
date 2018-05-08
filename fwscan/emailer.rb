require 'mail'

class Emailer
	@@log = Logger.new(STDOUT)

	def self.init(opts)
		@@log = opts[:logger] unless opts[:logger].nil?
	end

	def self.mail(opts)
		@@log.info "Mailing summary"

		body = opts[:body]

		puts "body=\n#{body}"

		subj = opts[:subject]
		from = opts[:email_from]
		to   = opts[:email_to]
		mailer = Mail.new do
			from     from
			to       to
			subject  subj
			body     body
		end

		#mailer.add_file(@file)
		mailer.charset = "UTF-8"

		@@log.debug mailer.to_s
		mailer.deliver
	rescue => e
		@@log.error "Failed to mail result: #{opts.inspect} [#{e.to_s}]"
		e.backtrace.each { |line|
			puts line
		}
	end
end
