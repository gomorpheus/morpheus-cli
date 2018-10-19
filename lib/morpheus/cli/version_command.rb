# a command for printing this client version
require 'morpheus/cli/cli_command'

class Morpheus::Cli::VersionCommand
  include Morpheus::Cli::CliCommand

  set_command_name :version
  def initialize
  end

  def usage
    "morpheus version"
  end

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on('-v','--short', "Print only the client version number") do |val|
        options[:short] = true
      end
      build_common_options(opts, options)
    end
    optparse.parse!(args)

    client_version = Morpheus::Cli::VERSION
    if options[:short]
      puts client_version
    else
      print cyan
      banner = "" +
        "   __  ___              __              \n" +
        "  /  |/  /__  _______  / /  ___ __ _____\n" +
        " / /|_/ / _ \\/ __/ _ \\/ _ \\/ -_) // (_-<\n" +
        "/_/  /_/\\___/_/ / .__/_//_/\\__/\\_,_/___/\n" +
        "****************************************"
      puts(banner)
      puts("  Client Version: #{client_version}")
      puts("****************************************")
      print reset
    end
  end
end
