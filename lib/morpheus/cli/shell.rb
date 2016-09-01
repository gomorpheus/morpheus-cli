# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'
require "shellwords"
require 'readline'


class Morpheus::Cli::Shell
	include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
		comp = proc do |s|
			command_list = Morpheus::Cli::CliRegistry.all.keys
			result = command_list.grep(/^#{Regexp.escape(s)}/)
			if result.nil? || result.empty?
				Readline::FILENAME_COMPLETION_PROC.call(s)
			else
				result
			end
		end

		Readline.completion_append_character = " "
		Readline.completion_proc = comp
	end

	def handle(args)
		usage = "Usage: morpheus shell"
		@command_options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on('-a','--account ACCOUNT', "Account Name") do |val|
				@command_options[:account_name] = val
      end
      opts.on('-A','--account-id ID', "Account ID") do |val|
				@command_options[:account_id] = val
      end
			opts.on('-C','--nocolor', "ANSI") do
				@command_options[:nocolor] = true
        Term::ANSIColor::coloring = false
      end
      opts.on( '-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
		end
		optparse.parse(args)

		history = []
		remote_handler = Morpheus::Cli::Remote.new()
		exit = false
		while !exit do
			input = Readline.readline("#{cyan}morpheus> #{reset}", true).to_s
			# print cyan,"morpheus > ",reset
			# input = $stdin.gets.chomp!
			if !input.empty?

				if input == 'exit'
					break
				elsif input == 'history'
					commands = history.last(100)
					puts "Last #{commands.size} commands"
					commands.reverse.each do |cmd|
						puts "#{cmd}"
					end
					next
				elsif input == 'clear'
					print "\e[H\e[2J"
					next
				elsif input == '!'
					input = history[-1]
				end

					begin
						history << input
						argv = Shellwords.shellsplit(input)
						if @command_options[:account_name]
							argv.push "--account", @command_options[:account_name]
						end
						if @command_options[:account_id]
							argv.push "--account-id", @command_options[:account_id]
						end
						if @command_options[:nocolor]
							argv.push "--nocolor"
						end
						#puts "cmd: #{argv.join(' ')}"
						if argv[0] == 'remote'
							remote_handler.handle(argv[1..-1])
						elsif Morpheus::Cli::CliRegistry.has_command?(argv[0])
							Morpheus::Cli::CliRegistry.exec(argv[0], argv[1..-1])
						else
							puts "Unrecognized Command."
						end
					rescue ArgumentError
						puts "Argument Syntax Error..."
					rescue SystemExit, Interrupt
							# nothing to do
					rescue => e
						print red, "\n", e.message, "\n", reset
						print e.backtrace.join("\n"), "\n"
					end
				
			end
		end
	end


	def get_prompt
		input = ''
		while char=STDIN.getch do
			if char == '\n'
				print "\r\n"
				puts "executing..."
				break
			end
			print char
			input << char
		end
		return input
	end
end
