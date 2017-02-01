
#
# require 'rubygems'
# require 'write_xlsx'
#
# # Create a new Excel workbook
# workbook = WriteXLSX.new('ruby.xlsx')
#
# # Add a worksheet
# worksheet = workbook.add_worksheet
#
# # Add and define a format
# format = workbook.add_format # Add a format
# format.set_bold
# format.set_color('red')
# format.set_align('center')
#
# # Write a formatted and unformatted string, row and column notation.
# col = row = 0
# worksheet.write(row, col, "Hi Excel!", format)
# worksheet.write(1,   col, "Hi Excel!")
#
# # Write a number and a formula using A1 notation
# worksheet.write('A3', 1.2345)
# worksheet.write('A4', '=SIN(PI()/4)')
#
# workbook.close
#
require 'write_xlsx'

class FormatXLSX
	@@log = nil
	def self.init(opts)
		@@log = opts[:logger]
		raise "Logger not set in FWLog" if @@log.nil?
	end

	attr_reader :file
	def initialize(file, label, opts={:force=>false})
		file.strip!
		file+=".xlsx" if file[/\.xlsx$/i].nil?
		@file=file
		if File.exists?(@file)
			raise "File exists #{@file}" if !opts[:force]
			$log.info "Overwriting file #{@file}"
		end
		@workbook = WriteXLSX.new(@file)
		@worksheet = @workbook.add_worksheet(label)
		@@log.info "Opened workbook #{@file}"
	end

	def write_headers(row, col, array)
		format = @workbook.add_format
		format.set_color('light grey')
		format.set_align('center')
		array.each { |entry|
			@worksheet.write(row, col, "#{entry}", format)
			col += 1
		}
		return row+1
	end

	def write_row(row, col, array)
		array.each { |entry|
			@@log.debug "Writing row,col=#{row},#{col}: #{array.to_json}"
			@worksheet.write(row, col, "#{entry}")
			col+=1
		}
		return row+1
	end

	def close
		@@log.info "Closing workbook #{@file}"
		@workbook.close
	end
end

