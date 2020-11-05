#!/usr/bin/env ruby

require 'glimmer-dsl-tk'

class HelloComputed
  class Contact
    attr_accessor :first_name, :last_name, :year_of_birth

    def initialize(attribute_map)
		 @reset = attribute_map
		 reset_contact
    end

	 def reset_contact
		 @first_name = @reset[:first_name]
       @last_name = @reset[:last_name]
       @year_of_birth = @reset[:year_of_birth]
	 end

    def name
      "#{first_name} #{last_name}"
    end

    def age
      Time.now.year - year_of_birth.to_i
    rescue
      0
    end
  end
end

class HelloComputed
  include Glimmer

  def initialize
	  @contact = Contact.new(
		 first_name: 'Barry',
		 last_name: 'McKibbin',
		 year_of_birth: 1985
	  )
  end

  def launch
    root {
      title 'Hello, Computed!'

      frame {
        grid column: 0, row: 0, padx: 5, pady: 5

        label {
          grid column: 0, row: 0, sticky: 'w'
          text 'First Name: '
        }
        entry {
          grid column: 1, row: 0
          width 15
          text bind(@contact, :first_name)
        }

        label {
          grid column: 0, row: 1, sticky: 'w'
          text 'Last Name: '
        }
        entry {
          grid column: 1, row: 1
          width 15
          text bind(@contact, :last_name)
        }

        label {
          grid column: 0, row: 2, sticky: 'w'
          text 'Year of Birth: '
        }
        entry {
          grid column: 1, row: 2
          width 15
          text bind(@contact, :year_of_birth)
        }

        label {
          grid column: 0, row: 3, sticky: 'w'
          text 'Name: '
        }
        label {
          grid column: 1, row: 3, sticky: 'w'
          text bind(@contact, :name, computed_by: [:first_name, :last_name])
        }

        label {
          grid column: 0, row: 4, sticky: 'w'
          text 'Age: '
        }
        label {
          grid column: 1, row: 4, sticky: 'w'
          text bind(@contact, :age, on_write: :to_i, computed_by: [:year_of_birth])
        }
		  button {
				grid column: 1, row: 5, sticky: 'w'
				text "Reset contact"
				command {
					@contact.reset_contact
			    }
			  }
      }
    }.open
  end
end

HelloComputed.new.launch
