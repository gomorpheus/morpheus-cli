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

  def self.instance
    @@instance
  end

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    #connect()
    #raise "one shell only" if @@instance
    @@instance = self
    recalculate_auto_complete_commands()
  end

  # def connect(opts)
  #   @api_client = establish_remote_appliance_connection(opts)
  # end

  def recalculate_auto_complete_commands
    @morpheus_commands = Morpheus::Cli::CliRegistry.all.keys.reject {|k| [:shell].include?(k) }
    @shell_commands = [:clear, :history, :'flush-history', :reload!, :help, :exit]
    @alias_commands = Morpheus::Cli::CliRegistry.all_aliases.keys
    @exploded_commands = []
    Morpheus::Cli::CliRegistry.all.each do |cmd, klass|
      @exploded_commands << cmd.to_s
      subcommands = klass.subcommands rescue []
      subcommands.keys.each do |sub_cmd|
        @exploded_commands << "#{cmd} #{sub_cmd}"
      end
    end
    @auto_complete_commands = (@exploded_commands + @shell_commands + @alias_commands).collect {|it| it.to_s }
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
    usage = "Usage: morpheus #{command_name}"
    @command_options = {} # this is a way to curry options to all commands.. but meh
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

        execute_commands(input)
      end
    end

    def execute_commands(input)
      # split the command on unquoted semicolons.
      # so you can run multiple commands at once! eg hosts list; instances list
      # all_commands = input.gsub(/(\;)(?=(?:[^"]|"[^"]*")*$)/, '__CMDDELIM__').split('__CMDDELIM__').collect {|it| it.to_s.strip }.select {|it| !it.empty?  }.compact
      all_commands = input.gsub(/(\;)(?=(?:[^"']|"[^'"]*")*$)/, '__CMDDELIM__').split('__CMDDELIM__').collect {|it| it.to_s.strip }.select {|it| !it.empty?  }.compact
      #puts "executing #{all_commands.size} commands: #{all_commands}"
      all_commands.each do |cmd|
        execute_command(cmd)
      end
      # skip logging of exit and !cmd
      unless input.strip.empty? || (["exit"].include?(input.strip)) || input.strip[0].to_s.chr == "!"
        log_history_command(input.strip)
      end
    end

    def execute_command(input)
      #puts "shell execute_command(#{input})"
      @command_options = {}

      input = input.to_s.strip

      # print cyan,"morpheus > ",reset
      # input = $stdin.gets.chomp!
      if !input.empty?

        if input == 'exit'
          #print cyan,"Goodbye\n",reset
          @history_logger.info "exit" if @history_logger
          exit 0
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
          return 0
        elsif input =~ /^history/
          n_commands = input.sub(/^history\s?/, '').sub(/\-n\s?/, '')
          n_commands = n_commands.empty? ? 25 : n_commands.to_i
          cmd_numbers = @history.keys.last(n_commands)
          puts "Last #{cmd_numbers.size} commands"
          cmd_numbers.each do |cmd_number|
            cmd = @history[cmd_number]
            puts "#{cmd_number.to_s.rjust(3, ' ')}  #{cmd}"
          end
          return 0
        elsif input == 'clear'
          print "\e[H\e[2J"
          return 0
        elsif input == 'flush-history' || input == 'flush_history'
          file_path = history_file_path
          if File.exists?(file_path)
            File.truncate(file_path, 0)
          end
          @history = {}
          @last_command_number = 0
          @history_logger = load_history_logger
          puts "history cleared!"
          return 0
        elsif input == 'reload' || input == 'reload!'
          #log_history_command(input)
          # could just fork instead?
          Morpheus::Cli.load!
          Morpheus::Cli::ConfigFile.instance.reload_file
          # initialize()
          # gotta reload appliance, groups, credentials
          @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
          recalculate_auto_complete_commands()
          begin
            load __FILE__
          rescue => err
            print "failed to reload #{__FILE__}. oh well"
            # print err
          end
          print dark,"Your shell has been reloaded",reset,"\n"
          return 0
        elsif input == '!!'
          cmd_number = @history.keys[-1]
          input = @history[cmd_number]
          if !input
            puts "There is no previous command"
            return 1
          end
          execute_commands(input)
        elsif input =~ /^\!.+/
          cmd_number = input.sub("!", "").to_i
          if cmd_number != 0
            input = @history[cmd_number]
            if !input
              puts "Command not found by number #{cmd_number}"
              return 0
            end
            #puts "executing history command: (#{cmd_number}) #{input}"
            execute_commands(input)
            return 0
          end
        elsif input =~ /^log_level/ # hidden for now
          log_level = input.sub(/^log_level\s*/, '').strip
          if log_level == ""
            puts "#{Morpheus::Logging.log_level}"
          elsif log_level == "debug"
            #log_history_command(input)
            @command_options[:debug] = true
            Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          elsif log_level == "info"
            #log_history_command(input)
            @command_options.delete(:debug)
            Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::INFO)
          elsif log_level.to_s == "0" || (log_level.to_i > 0 && log_level.to_i < 7)
            # other log levels are pointless right now..
            @command_options.delete(:debug)
            Morpheus::Logging.set_log_level(log_level.to_i)
          else
            print_red_alert "unknown log level: #{log_level}"
          end
          return 0
        # lots of hidden commands
        elsif input == "debug"
          @command_options[:debug] = true
          Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          return 0
        elsif ["hello","hi","hey","hola"].include?(input.strip.downcase)
          print "#{input.capitalize}, how may I #{cyan}help#{reset} you?\n"
          return
        elsif input == "colorize"
          Term::ANSIColor::coloring = true
          @command_options[:nocolor] = false
          return 0
        elsif input == "uncolorize"
          Term::ANSIColor::coloring = false
          @command_options[:nocolor] = true
          return 0
        elsif input == "shell"
          print "#{cyan}You are already in a shell.#{reset}\n"
          return false
        end

        begin
          argv = Shellwords.shellsplit(input)


          if Morpheus::Cli::CliRegistry.has_command?(argv[0]) || Morpheus::Cli::CliRegistry.has_alias?(argv[0])
            #log_history_command(input)
            Morpheus::Cli::CliRegistry.exec(argv[0], argv[1..-1])
          else
            print_yellow_warning "Unrecognized Command '#{argv[0]}'. Try 'help' to see a list of available commands."
            @history_logger.warn "Unrecognized Command #{argv[0]}" if @history_logger
            #puts optparse
          end
          # rescue ArgumentError
          #   puts "Argument Syntax Error..."
        rescue Interrupt
          # nothing to do
          @history_logger.warn "shell interrupt" if @history_logger
          print "\nInterrupt. aborting command '#{input}'\n"
        rescue SystemExit
          # nothing to do
          # print "\n"
        rescue => e
          @history_logger.error "#{e.message}" if @history_logger
          Morpheus::Cli::ErrorHandler.new.handle_error(e, @command_options)
          # exit 1
        end

        if @return_to_log_level
          Morpheus::Logging.set_log_level(@return_to_log_level)
          @return_to_log_level = nil
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
        #   "#{msg}\n"
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
