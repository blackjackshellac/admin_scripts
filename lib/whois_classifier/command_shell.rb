#
# http://bogojoker.com/readline/
#
require 'readline'
require 'abbrev'

module CommandShell
	class CLI 

		@@log = nil

		DEF_OPTS={
			:prompt => "> ",
			:mode => :vi
		}

		COMPLETION = Proc.new { |s|
			s.strip!
			if s.empty?
				puts @commands.join(", ")
				return s
			end
			@commandh.key?(s) ? @commandh[s] : s
		}

		attr_accessor :prompt, :action
		attr_reader :commands, :commandh, :commanda, :command, :args
		def initialize(opts=DEF_OPTS)
			@prompt = opts[:prompt]||DEF_OPTS[:prompt]
			@mode = opts[:mode]||DEF_OPTS[:mode]
			@procs = {}
			@action = opts[:action]||:running

			@command = ""
			@args = ""
			@commands = []

			Readline.completion_append_character = " "
			Readline.completion_proc = proc { |s| COMPLETION.call(s) }

			edit_mode(@mode)
		end

		def self.init(opts)
			@@log = opts[:logger]
		end

		def set_commands(c)
			@commands = c
			@commandh = c.abbrev
			@commanda = commandh.keys
		end

		def command_proc(c, cproc)
			@procs[c] = cproc
		end

		def prompt(l)
			@action = l.to_sym if @commands.include?(l)
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

		def shell 
			# Store the state of the terminal
			stty_save = %x/stty -g/.chomp

			begin
				while line = readline_with_history
					@cmd,@args = line.split(/\s+/, 2)
					@args = "" if @args.nil?
					cproc = @procs[@cmd]
					if cproc.nil?
						p line
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

