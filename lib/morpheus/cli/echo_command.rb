require 'morpheus/cli/cli_command'
require 'term/ansicolor'
require 'json'

# This is for use in dotfile scripts for printing
# It is also responsible for maintaining a map of variables
# that are also used in custom shell prompts.
class Morpheus::Cli::Echo
  include Morpheus::Cli::CliCommand
  set_command_name :echo
  set_command_hidden

  unless defined?(DEFAULT_VARIABLE_MAP)
    DEFAULT_VARIABLE_MAP = {'%cyan' => Term::ANSIColor.cyan, '%magenta' => Term::ANSIColor.magenta, '%red' => Term::ANSIColor.red, '%green' => Term::ANSIColor.green, '%yellow' => Term::ANSIColor.yellow, '%white' => Term::ANSIColor.white, '%dark' => Term::ANSIColor.dark, '%reset' => Term::ANSIColor.reset}
  end

  def self.variable_map
    @output_variable_map ||= recalculate_variable_map()
  end

  def self.recalculate_variable_map()
    var_map = {}
    var_map.merge!(DEFAULT_VARIABLE_MAP)
    appliance = ::Morpheus::Cli::Remote.load_active_remote()
    if appliance
      var_map.merge!({'%remote' => appliance[:name], '%remote_url' => appliance[:host], '%username' => appliance[:username]})
    end
    @output_variable_map = var_map
  end

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [<message>]"
      opts.on( '-n', '--nonewline', "do not append a newline to your words" ) do
        append_newline = false
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    out = ""
    out << args.join(' ')

    self.class.variable_map.each do |k, v|
      out.gsub!(k.to_s, v.to_s)
    end
    if append_newline
      out << "\n"
    end
    # print out 
    print cyan + out + reset
    return 0
  end

end
