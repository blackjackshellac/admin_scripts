#
# http://bogojoker.com/readline/
#
require 'readline'
require 'abbrev'

module CommandShell
	class CLI 

		@@log = nil
		@@procs = {}

		@@commands = []
		@@commanda = []
		@@commandh = {}

		DEF_OPTS={
			:prompt => "> ",
			:mode => :vi,
			:commands => [],
			:action => :execute
		}

		COMPLETION = Proc.new { |s|
			commands = CommandShell::CLI.commands
			commandh = CommandShell::CLI.commandh
			s=s.strip
			if s.empty?
				puts commands.join(", ")
			elsif commandh.key?(s)
				s=commandh[s]
			else
				s=""
			end
			s
		}

		attr_accessor :prompt, :action
		attr_reader :command, :args
		def initialize(execute_proc, opts=DEF_OPTS)
			@prompt = get_opt(opts,:prompt)
			@mode = get_opt(opts,:mode)
			@action = get_opt(opts,:action)

			@@procs[:execute] = execute_proc
			@@procs[:completion] = opts[:completion]||COMPLETION

			@command = ""
			@args = ""

			CommandShell::CLI.set_commands(get_opt(opts, :commands))

			Readline.completion_append_character = " "
			Readline.completion_proc = @@procs[:completion] #proc { |s| COMPLETION.call(s) }

			edit_mode(@mode)
		end

		def get_opt(opts, key)
			opt=opts[key]||DEF_OPTS[key]
			raise "No option found for key=:#{key}" if opt.nil?
			opt
		end

		def self.init(opts)
			@@log = opts[:logger]
		end

		def self.set_commands(c)
			@@commands = c
			@@commandh = c.abbrev
			@@commanda = @@commandh.keys
		end

		def self.commands
			@@commands
		end

		def self.commanda
			@@commanda
		end

		def self.commandh
			@@commandh
		end

		def command_proc(c, cproc)
			@@procs[c] = cproc
		end

		def prompt(l)
			raise "Action #{l} not found in commands: #{@@commands.join(',')}" unless @@commands.include?(l)
			@action = l.to_sym
			@prompt = "#{l}> "
		end

		def edit_mode(mode)
			# Default
			libedit = false

			# If NotImplemented then this might be libedit
			begin
				mode == :emacs ? Readline.emacs_editing_mode : Readline.vi_editing_mode
			rescue NotImplementedError
				libedit = true
			end
		end

		def readline_with_history
			line = Readline.readline(@prompt, true)
			return nil if line.nil?
			
			Readline::HISTORY.pop if line =~ /^\s*$/ || Readline::HISTORY.to_a[-2] == line

			line.strip
		end

		def history
			Readline::HISTORY.to_a.each { |line|
				puts line
			}
		end

		def shell 
			# Store the state of the terminal
			stty_save = %x/stty -g/.chomp

			begin
				while line = readline_with_history
					@cmd,@args = line.split(/\s+/, 2)
					@args = "" if @args.nil?
					cproc = @@procs[@cmd]
					if cproc.nil?
						cproc = @@procs[:execute]
						cproc.call(self, line)
					else
						@@log.debug "Calling proc #{@cmd}"
						cproc.call(self)
					end
					break if @action == :quit
				end
			rescue Interrupt => e
				system('stty', stty_save) # Restore
			end
		end

	end #CLI
end #CommandShell

