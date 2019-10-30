require 'fileutils'
require 'time'
require 'morpheus/cli/cli_registry'
require 'morpheus/logging'
require 'term/ansicolor'

class Morpheus::Cli::DotFile
  include Term::ANSIColor

  EXPORTED_ALIASES_HEADER = "# exported aliases"

  # the path of the profile source file
  # this is executed when `morpheus` is run
  def self.morpheus_profile_filename
    File.join(Morpheus::Cli.home_directory, ".morpheus_profile")
  end

  # the path of the shell source file
  # this is executed when `morpheus shell` is run
  def self.morpheusrc_filename
    File.join(Morpheus::Cli.home_directory, ".morpheusrc")
  end

  attr_reader :filename
  # attr_reader :file_contents
  # attr_reader :commands
  # attr_reader :cmd_results

  def initialize(fn)
    @filename = fn
    #load_file()
  end

  # execute this file as a morpheus shell script
  # @param stop_on_failure [true, false] the will halt execution if a command returns false. 
  #   Default is false, keep going...
  # @block [Proc] if a block is given, each command in the file will be yielded to it
  #   The default is executes the command with the CliRegistry.exec(cmd, args)
  # @return [Array] exit codes of all the commands that were run.
  def execute(stop_on_failure=false, &block)
    if !File.exists?(@filename)
      print "#{Term::ANSIColor.red}source file not found: #{@filename}#{Term::ANSIColor.reset}\n" # if Morpheus::Logging.debug?
    else
      Morpheus::Logging::DarkPrinter.puts "executing source file #{@filename}" if Morpheus::Logging.debug?
    end
    file_contents = File.read(@filename)
    lines = file_contents.split("\n")
    cmd_results = []
    line_num = 0
    lines.each_with_index do |line, line_index|
      line_num = line_index + 1
      line = line.strip
      next if line.empty?
      next if line =~ /^\#/ # skip comments
      
      cmd_exit_code = 0
      cmd_err = nil
      cmd_result = nil
      begin
        cmd_result = Morpheus::Cli::CliRegistry.exec_expression(line)
      rescue SystemExit => err
        if err.success?
          cmd_result = true
        else
          puts "#{red} source file: #{@filename}, line: #{line_num}, command: #{line}, error: #{err}#{reset}"
          cmd_result = false
        end
      rescue => err
        # raise err
        puts "#{red} source file: #{@filename}, line: #{line_num}, command: #{line}, error: #{err}#{reset}"
        cmd_result = false
      end
      if cmd_result == false
        if stop_on_failure
          return cmd_results
        end
      end
    end
    return cmd_results
  end

  # this saves the source file, upserting alias definitions at the bottom
  # todo: smarter logic to allow the user to put stuff AFTER this section too
  # under the section titled '# exported aliases'
  # @param alias_definitions [Map] Map of alias_name => command_string
  # @return nil
  def export_aliases(alias_definitions)
    if !@filename
      print "#{Term::ANSIColor.dark}Skipping source file save because filename has not been set#{Term::ANSIColor.reset}\n" if Morpheus::Logging.debug?
      return false
    end
    if !Dir.exists?(File.dirname(@filename))
      FileUtils.mkdir_p(File.dirname(@filename))
    end
    if !File.exists?(@filename)
      print "#{Term::ANSIColor.dark}Initializing source file #{@filename}#{Term::ANSIColor.reset}\n" if Morpheus::Logging.debug?
      FileUtils.touch(@filename)
    else
      print "#{dark} #=> Saving source file #{@filename}#{reset}\n" if Morpheus::Logging.debug?
    end


    config_text = File.read(@filename)
    config_lines = config_text.split(/\n/)
    new_config_lines = []
    existing_alias_definitions = {}
    header_line_index = config_lines.index {|line| line.strip.include?(EXPORTED_ALIASES_HEADER) }
    # JD: there's some bad bug here where it can clear all your aliases!
    # it would be safer to export to another file at .morpheus/aliases or something.
    if header_line_index
      # keep everything before the exported alias section
      new_config_lines = config_lines[0..header_line_index-1]
      existing_alias_lines = config_lines[header_line_index..config_lines.size-1]
      # parse out the existing alias definitions
      existing_alias_lines.each do |line|
        if line =~ /^alias\s+/
          alias_name, command_string = Morpheus::Cli::CliRegistry.parse_alias_definition(line)
          if alias_name.empty? || command_string.empty?
            print "#{dark} #=> removing bad config line #{line_num} invalid alias definition: #{line}\n" if Morpheus::Logging.debug?
          else
            existing_alias_definitions[alias_name] = command_string
          end
        end
      end
    else
      new_config_lines = config_lines
      new_config_lines << "" # blank line before alias header
    end

    # append header line
    new_config_lines << EXPORTED_ALIASES_HEADER
    new_config_lines << "# Do not put anything below here, or it will be lost when aliases are exported"
    #new_config_lines << ""

    # update aliases, sort them, and append the lines
    new_alias_definitions = existing_alias_definitions.merge(alias_definitions)
    new_alias_definitions.keys.sort.each do |alias_name|
      new_config_lines << "alias #{alias_name}='#{new_alias_definitions[alias_name]}'"
    end
    
    # include a blank line after this section
    new_config_lines << ""
    new_config_lines << ""

    new_config_text = new_config_lines.join("\n")
    
    File.open(@filename, 'w') {|f| f.write(new_config_text) }
    return true
  end

  # this saves the source file, removing alias definitions at the bottom
  # todo: smarter logic to allow the user to put stuff AFTER this section too
  # under the section titled '# exported aliases'
  # @param alias_definitions [Map] Map of alias_name => command_string
  # @return nil
  def remove_aliases(alias_names)
    if !@filename
      print "#{Term::ANSIColor.dark}Skipping source file save because filename has not been set#{Term::ANSIColor.reset}\n" if Morpheus::Logging.debug?
      return false
    end
    if !Dir.exists?(File.dirname(@filename))
      FileUtils.mkdir_p(File.dirname(@filename))
    end
    if !File.exists?(@filename)
      print "#{Term::ANSIColor.dark}Initializing source file #{@filename}#{Term::ANSIColor.reset}\n" if Morpheus::Logging.debug?
      FileUtils.touch(@filename)
    else
      print "#{dark} #=> Saving source file #{@filename}#{reset}\n" if Morpheus::Logging.debug?
    end


    config_text = File.read(@filename)
    config_lines = config_text.split(/\n/)
    
    new_config_lines = config_lines.reject {|line|
      alias_names.find {|alias_name| /^alias\s+#{Regexp.escape(alias_name)}\s?\=/ }
    }
    
    new_config_text = new_config_lines.join("\n")
    
    File.open(@filename, 'w') {|f| f.write(new_config_text) }
    return true
  end



end
