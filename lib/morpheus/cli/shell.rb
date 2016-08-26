# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'
require "shellwords"


class Morpheus::Cli::Shell
	include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
	end

	def handle(args) 
		
		exit = false
		while !exit do
			print red,"morpheus > ",reset	
			input = $stdin.gets.chomp!
			if !input.empty?
				if input == 'exit'
					break
				end
				argv = Shellwords.shellsplit(input)

				if Morpheus::Cli::CliRegistry.has_command?(argv[0])
					begin
						Morpheus::Cli::CliRegistry.exec(argv[0], argv[1..-1])
					rescue SystemExit, Interrupt
						# nothing to do
					end
				end
			end
		end
	end
end
