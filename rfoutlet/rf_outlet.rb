
class RFOutlet
	ON  = "on"
	OFF = "off"

	@@codesend="/var/www/html/rfoutlet/codesend"

	attr_reader :label, :name, :code, :on, :off
	def initialize(label, h)
		@label = label
		@name = h[:name]
		@code = h[:code]
		@on   = h[:on]
		@off  = h[:off]
	end

	def get_rfcode(state)
		(state.eql?(ON) ? @on : @off)
	end

	def sendcode(rfcode)
		# return output
		%x[#{@@codesend} #{rfcode}].strip
	end

	def to_s
		"%s: %s [%s]" % [ @label, @name, @code ]
	end

end


