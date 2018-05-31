#!/usr/bin/env ruby
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli'
require 'morpheus/rest_client'
require 'morpheus/cli/cli_registry'
require 'morpheus/cli/dot_file'
require 'morpheus/cli/error_handler'
require 'morpheus/logging'
require 'morpheus/cli'

module Morpheus
  
  # Terminal is a class for executing morpheus commands
  # The default IO is STDIN, STDOUT, STDERR
  # The default home directory is $HOME/.morpheus
  #
  # ==== Example Usage
  #
  #    morph = Morpheus::Terminal.new
  #    exit_code, err = morph.execute("instances list -m 10")
  #    assert exit_code == 0
  #    assert err == nil
  #
  #    morph = Morpheus::Terminal.new(STDIN, File.new("/tmp/morph.log", "w+"))
  #    morph.execute("hosts get 23")
  #
  #    morph = Morpheus::Terminal.new(STDIN, File.new("/tmp/host23.json", "w"))
  #    morph.execute("hosts get 23 --json")
  #    puts File.read("/tmp/host23.json")
  #
  class Terminal
    
    # todo: this can be combined with Cli::Shell

    class Blackhole # < IO
      def accrete_data(*mgs)
        # Singularity.push(*msgs)
        return nil
      end
      alias :print :accrete_data
      alias :puts :accrete_data
      alias :'<<' :accrete_data
      alias :write :accrete_data
      alias :write :accrete_data
      # alias :gets :do_nothing
    end

    # DEFAULT_TERMINAL_WIDTH = 80
    
    def self.default_color
      Term::ANSIColor.cyan
    end

    def self.prompt
      if @prompt.nil?
        if ENV['MORPHEUS_PS1']
          @prompt = ENV['MORPHEUS_PS1'].dup
        else
          #ENV['MORPHEUS_PS1'] = "#{Term::ANSIColor.cyan}morpheus> #{Term::ANSIColor.reset}"
          @prompt = "#{Term::ANSIColor.cyan}morpheus>#{Term::ANSIColor.reset} "
        end
      end
      @prompt
    end

    def self.prompt=(v)
      @prompt = v
    end

    def self.angry_prompt
      "#{Term::ANSIColor.red}morpheus:#{Term::ANSIColor.reset} "
    end

    def self.custom_prompt
      #export MORPHEUS_PS1='\[\e[1;32m\]\u@\h:\w${text}$\[\e[m\] '
    end

    # the global Morpheus::Terminal instance
    # This should go away, but it needed for now...
    def self.instance
      @morphterm
    end

    # hack alert! This should go away, but it needed for now...
    def self.new(*args)
      obj = super(*args)
      @morphterm = obj
      obj
    end

    attr_accessor :prompt #, :angry_prompt
    attr_reader :stdin, :stdout, :stderr, :home_directory


    # Create a new instance of Morpheus::Terminal
    # @param stdin  [IO] Default is STDIN
    # @param stdout [IO] Default is STDOUT
    # @param stderr [IO] Default is STDERR
    # @param [IO] stderr
    # @stderr = stderr
    def initialize(stdin=STDIN,stdout=STDOUT, stderr=STDERR, homedir=nil)
      # todo: establish config context for executing commands, 
    #       so you can run them in parallel within the same process
    #       that means not using globals and class instance vars
    #       just return an exit code / err, instead of raising SystemExit
    
      
      # establish IO
      # @stdin, @stdout, @stderr = stdin, stdout, stderr
      set_stdin(stdin)
      set_stdout(stdout)
      set_stderr(stderr)
      
      # establish home directory
      use_homedir = homedir || ENV['MORPHEUS_CLI_HOME'] || File.join(Dir.home, ".morpheus")
      set_home_directory(use_homedir)
      
      # use colors by default
      set_coloring(STDOUT.isatty)
      # Term::ANSIColor::coloring = STDOUT.isatty
      # @coloring = Term::ANSIColor::coloring?

      # startup script
      if File.exists? Morpheus::Cli::DotFile.morpheus_profile_filename
        @profile_dot_file = Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheus_profile_filename)
      else
        @profile_dot_file = nil
      end
      
      # the string to prompt for input with
      @prompt ||= Morpheus::Terminal.prompt
      @angry_prompt ||= Morpheus::Terminal.angry_prompt
    end

    # execute .morpheus_profile startup script
    def execute_profile_script(rerun=false)
      if @profile_dot_file
        if rerun || !@profile_dot_file_has_run
          @profile_dot_file_has_run = true
          return @profile_dot_file.execute() # todo: pass io in here
        else
          return false # already run
        end
      else
        return nil
      end
    end

    def set_stdin(io)
      # if io.nil? || io == 'blackhole' || io == '/dev/null'
      #   @stdout = Morpheus::Terminal::Blackhole.new
      # else
      #   @stdout = io
      # end
      @stdin = io
    end

    def set_stdout(io)
      if io.nil? || io == 'blackhole' || io == '/dev/null'
        @stdout = Morpheus::Terminal::Blackhole.new
      else
        @stdout = io
      end
      @stdout
    end

    def set_stderr(io)
      if io.nil? || io == 'blackhole' || io == '/dev/null'
        @stderr = Morpheus::Terminal::Blackhole.new
      else
        @stderr = io
      end
      @stderr
    end

    def set_home_directory(homedir)
      full_homedir = File.expand_path(homedir)
      # if !Dir.exists?(full_homedir)
      #   print_red_alert "Directory not found: #{full_homedir}"
      #   exit 1
      # end
      @home_directory = full_homedir
      
      # todo: deprecate this
      Morpheus::Cli.home_directory = full_homedir

      @home_directory
    end

    # def coloring=(v)
    #   set_coloring(enabled)
    # end

    def set_coloring(enabled)
      @coloring = !!enabled
      Term::ANSIColor::coloring = @coloring
      coloring?
    end

    def coloring?
      @coloring == true
    end

    # alias :'coloring=' :set_coloring

    def usage
      out = "Usage: morpheus [command] [options]\n"
      # just for printing help. todo: start using this. maybe in class Cli::MainCommand
      # maybe OptionParser's recover() instance method will do the trick
      optparse = Morpheus::Cli::OptionParser.new do|opts|
        opts.banner = "Options:" # hack alert
        opts.on('-v','--version', "Print the version.") do
          @stdout.puts Morpheus::Cli::VERSION
          # exit
        end
        opts.on('--noprofile','--noprofile', "Do not read and execute the personal initialization script .morpheus_profile") do
          @noprofile = true
        end
        opts.on('-C','--nocolor', "Disable ANSI coloring") do
          @coloring = false
          Term::ANSIColor::coloring = false
        end
        opts.on('-V','--debug', "Print extra output for debugging.") do |json|
          @terminal_log_level = Morpheus::Logging::Logger::DEBUG
          Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
        end
        opts.on( '-h', '--help', "Prints this help" ) do
          @stdout.puts opts
          # exit
        end
      end
      out << "Commands:\n"
      Morpheus::Cli::CliRegistry.all.keys.sort.each {|cmd|
        out << "\t#{cmd.to_s}\n"
      }
      # out << "Options:\n"
      out << optparse.to_s
      out << "\n"
      out << "For more information, see https://github.com/gomorpheus/morpheus-cli/wiki"
      out << "\n"
      out
    end

    def prompt
      @prompt # ||= Morpheus::Terminal.default_prompt
    end

    def prompt=(str)
      @prompt = str
    end

    def angry_prompt
      @angry_prompt ||= Morpheus::Terminal.angry_prompt
    end

    # def gets
    #   Readline.completion_append_character = " "
    #   Readline.completion_proc = @auto_complete
    #   Readline.basic_word_break_characters = ""
    #   #Readline.basic_word_break_characters = "\t\n\"\‘`@$><=;|&{( "
    #   input = Readline.readline("#{@prompt}", true).to_s
    #   input = input.strip
    #   execute(input)
    # end

    # def puts(*cmds)
    #   cmds.each do |cmd|
    #     self.execute(cmd) # exec
    #   end
    # end

    # def gets(*args)
    #   $stdin.gets(*args)
    # end

# protected

    def execute(input)
      Morpheus::Logging::DarkPrinter.puts "Terminal input: (#{input.class}) #{input}"
      exit_code = 0
      err = nil
      args = nil
      if input.is_a? String
        Morpheus::Logging::DarkPrinter.puts  "Terminal Shellwords.shellsplit(): #{input}"
        args = Shellwords.shellsplit(input)
      elsif input.is_a?(Array)
        args = input.dup
      else
        raise "terminal execute() expects a String to be split or an Array of String arguments and instead got (#{args.class}) #{args}"
      end

      # include Term::ANSIColor # tempting

      # short circuit version switch
      if args.length == 1
        if args[0] == '-v' || args[0] == '--version'
          @stdout.puts Morpheus::Cli::VERSION
          return 0, nil
        end
      end

      # looking for global help?
      if args.length == 1
        if args[0] == '-h' || args[0] == '--help' || args[0] == 'help'
          @stdout.puts usage
          return 0, nil
        end
      end
      

      # process global options

      # raise log level right away
      if args.find {|it| it == '-V' || it == '--debug'}
        @terminal_log_level = Morpheus::Logging::Logger::DEBUG
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      end

      # execute startup script .morpheus_profile  unless --noprofile is passed
      # todo: this should happen in initialize..
      noprofile = false
      if args.find {|it| it == '--noprofile' }
        noprofile = true
        args.delete_if {|it| it == '--noprofile' }
      end

      if @profile_dot_file && !@profile_dot_file_has_run
        if !noprofile && File.exists?(@profile_dot_file.filename)
          execute_profile_script()
        end
      end

      # not enough arguments?
      if args.count == 0
        @stderr.puts "#{@angry_prompt}[command] argument is required."
        #@stderr.puts "No command given, here's some help:"
        @stderr.print usage
        return 2, nil # CommandError.new("morpheus requires a command")
      end
      
      cmd_name = args[0]
      cmd_args = args[1..-1]

      # unknown command?
      # all commands should be registered commands or aliases
      if !(Morpheus::Cli::CliRegistry.has_command?(cmd_name) || Morpheus::Cli::CliRegistry.has_alias?(cmd_name))
        @stderr.puts "#{@angry_prompt}'#{cmd_name}' is not a morpheus command. See 'morpheus --help'."
        #@stderr.puts usage
        return 127, nil
      end

      # ok, execute the command (or alias)
      result = nil
      begin
        # shell is a Singleton command class
        if args[0] == "shell"
          result = Morpheus::Cli::Shell.instance.handle(args[1..-1])
        else
          result = Morpheus::Cli::CliRegistry.exec(args[0], args[1..-1])
        end
        # todo: clean up CliCommand return values, handle a few diff types for now
        if result == nil || result == true || result == 0
          exit_code = 0
        elsif result == false
          exit_code = 1
        elsif result.is_a?(Array) # exit_code, err
          exit_code = result[0] #.to_i
          err = result[1]
        else
          exit_code = result #.to_i
        end
      rescue => e
        exit_code = Morpheus::Cli::ErrorHandler.new(@stderr).handle_error(e)
        err = e
      end

      return exit_code, err

    end

  end
end

