# a command for printing this client version
require 'morpheus/cli/cli_command'

class Morpheus::Cli::VersionCommand
  include Morpheus::Cli::CliCommand

  cli_command_name :version
  
	def initialize
	end

	def handle(args)
		client_version = Morpheus::Cli::VERSION
		 if args && args[0] == '-v'
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
