# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require "shellwords"
require 'readline'
require 'logger'
require 'fileutils'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/error_handler'


class Morpheus::Cli::Shell
	include Morpheus::Cli::CliCommand

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
		@morpheus_commands = Morpheus::Cli::CliRegistry.all.keys.reject {|k| [:shell].include?(k) }
		@shell_commands = [:clear, :history, :'flush-history', :reload!, :help, :exit]
		@exploded_commands = []
		Morpheus::Cli::CliRegistry.all.each do |cmd, klass|
			@exploded_commands << cmd.to_s
			subcommands = klass.subcommands rescue []
			subcommands.keys.each do |sub_cmd| 
				@exploded_commands << "#{cmd} #{sub_cmd}"
			end
		end
		@auto_complete_commands = (@exploded_commands + @shell_commands).collect {|it| it.to_s }
		@auto_complete = proc do |s|
			command_list = @auto_complete_commands
			result = command_list.grep(/^#{Regexp.escape(s)}/)
			if result.nil? || result.empty?
				Readline::FILENAME_COMPLETION_PROC.call(s)
			else
				result
			end
		end

	end

	def handle(args)
		usage = "Usage: morpheus shell"
		@command_options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on('-C','--nocolor', "ANSI") do
				@command_options[:nocolor] = true
				Term::ANSIColor::coloring = false
			end
			opts.on('-V','--debug', "Print extra output for debugging. ") do |json|
				Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
				@command_options[:debug] = true
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
		end
		optparse.parse!(args)

		@history_logger ||= load_history_logger rescue nil
		@history_logger.info "shell started" if @history_logger
		load_history_from_log_file()

		exit = false
		while !exit do
			Readline.completion_append_character = " "
			Readline.completion_proc = @auto_complete
			Readline.basic_word_break_characters = ""
			#Readline.basic_word_break_characters = "\t\n\"\‘`@$><=;|&{( "
			input = Readline.readline("#{cyan}morpheus> #{reset}", true).to_s
			input = input.strip
			# print cyan,"morpheus > ",reset
			# input = $stdin.gets.chomp!
			if !input.empty?

				if input == 'exit'
					@history_logger.info "exit" if @history_logger
					break
				elsif input == 'help'

					puts "You are in a morpheus client shell." 
					puts "See the available commands below."


					puts "\nCommands:"
					# commands = @morpheus_commands + @shell_commands
					@morpheus_commands.sort.each {|cmd|
						puts "\t#{cmd.to_s}"
					}
					puts "\n"
					puts "\nShell Commands:"
					@shell_commands.each {|cmd|
						puts "\t#{cmd.to_s}"
					}
					puts "\n"
					puts "For more information."
					puts "See https://github.com/gomorpheus/morpheus-cli/wiki"
					print "\n"
					next
				elsif input =~ /^history/
					n_commands = input.sub(/^history\s?/, '').sub(/\-n\s?/, '')
					n_commands = n_commands.empty? ? 25 : n_commands.to_i
					cmd_numbers = @history.keys.last(n_commands)
					puts "Last #{cmd_numbers.size} commands"
					cmd_numbers.each do |cmd_number|
						cmd = @history[cmd_number]
						puts "#{cmd_number.to_s.rjust(3, ' ')}  #{cmd}"
					end
					next
				elsif input == 'clear'
					print "\e[H\e[2J"
					next
				elsif input == 'flush-history' || input == 'flush_history'
					file_path = history_file_path
					if File.exists?(file_path)
						File.truncate(file_path, 0)
					end
					@history = {}
					@last_command_number = 0
					@history_logger = load_history_logger
					puts "history cleared!"
					next
				elsif input == 'reload' || input == 'reload!'
					log_history_command(input)
					# could just fork instead?
					Morpheus::Cli.load!
					next
				elsif input == '!!'
					cmd_number = @history.keys[-1]
					input = @history[cmd_number]
					if !input
						puts "There is no previous command"
						next
					end
				elsif input =~ /^\!.+/
					cmd_number = input.sub("!", "").to_i
					if cmd_number != 0
						input = @history[cmd_number]
						if !input
							puts "Command not found by number #{cmd_number}"
							next
						end
					end
				elsif input =~ /^log_level/ # hidden for now
					log_level = input.split.last
					if log_level == "debug"
						log_history_command(input)
						@command_options[:debug] = true
						Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
					elsif log_level == "info"
						log_history_command(input)
						@command_options.delete(:debug)
						Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::INFO)
					else
						# other log levels are pointless right now..
						print_red_alert "unknown log level: #{log_level}"
					end
					next
				end

				begin
					argv = Shellwords.shellsplit(input)

					# set global log level to debug (print stack trace for bubbled exceptions)
					if argv.find {|arg| arg == '-V' || arg == '--debug'}
						@return_to_log_level = Morpheus::Logging.log_level
					  Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
					elsif @command_options[:debug]
						argv.push "--debug"
					end

					if argv[0] == 'shell'
						puts "You are already in a shell."
					elsif Morpheus::Cli::CliRegistry.has_command?(argv[0])
						log_history_command(input)
						Morpheus::Cli::CliRegistry.exec(argv[0], argv[1..-1])
					else
						@history_logger.warn "Unrecognized Command: '#{argv[0]}'" if @history_logger
						puts "Unrecognized Command '#{input}'. Try 'help'"
						#puts optparse
					end
				# rescue ArgumentError
				# 	puts "Argument Syntax Error..."
				rescue Interrupt
					# nothing to do
					@history_logger.warn "shell interrupt" if @history_logger
					puts "\nInterrupt. Aborting command '#{input}'"
					print "\n"
				rescue SystemExit
					# nothing to do
					print "\n"
				rescue => e
					@history_logger.error "#{e.message}" if @history_logger
					Morpheus::Cli::ErrorHandler.new.handle_error(e)
					# exit 1
				end

				if @return_to_log_level
					Morpheus::Logging.set_log_level(@return_to_log_level)
					@return_to_log_level = nil
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

	def history_file_path
		File.join(Dir.home, '.morpheus', "shell_history")
	end

	def load_history_logger
		file_path = history_file_path
		if !Dir.exists?(File.dirname(file_path))
			FileUtils.mkdir_p(File.dirname(file_path))
		end
		logger = Logger.new(file_path)
		# logger.formatter = proc do |severity, datetime, progname, msg|
		# 	"#{msg}\n"
		# end
		return logger
	end

	def load_history_from_log_file(n_commands=1000)
		@history ||= {}
		@last_command_number ||= 0

		begin
			if Gem.win_platform?
				return @history
			end
			file_path = history_file_path
			FileUtils.mkdir_p(File.dirname(file_path))
			# grab extra lines because not all log entries are commands
			n_lines = n_commands + 500
			history_lines = `tail -n #{n_lines} #{file_path}`.split(/\n/)
			command_lines = history_lines.select do |line| 
				line.match(/\(cmd (\d+)\) (.+)/)
			end
			command_lines = command_lines.last(n_commands)
			command_lines.each do |line|
				matches = line.match(/\(cmd (\d+)\) (.+)/)
				if matches && matches.size == 3
					cmd_number = matches[1].to_i
					cmd = matches[2]

					@last_command_number = cmd_number
					@history[@last_command_number] = cmd

					# for Ctrl+R history searching
					Readline::HISTORY << cmd
				end
			end
		rescue => e
			# raise e
			# puts "failed to load history from log"
			@history = {}
		end
		return @history
	end

	def log_history_command(cmd)
		@history ||= {}
		@last_command_number ||= 0
		@last_command_number += 1
		@history[@last_command_number] = cmd
		if @history_logger
			@history_logger.info "(cmd #{@last_command_number}) #{cmd}" 
		end
	end
end
