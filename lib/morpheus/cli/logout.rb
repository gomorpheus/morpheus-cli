# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/remote'
require 'morpheus/cli/credentials'
require 'json'

class Morpheus::Cli::Logout
  include Morpheus::Cli::CliCommand
  # include Morpheus::Cli::WhoamiHelper
  # include Morpheus::Cli::AccountsHelper
  
	def initialize() 
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
  end

	def usage
		"Usage: morpheus logout"
	end

	def handle(args)
		logout(args)
	end
	
	def logout(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, []) # todo: support :remote too perhaps
		end
		optparse.parse!(args)

		connect(options)

		begin

			creds = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
			if !creds
				print yellow,"\nYou are not logged in to #{@appliance_name} - #{@appliance_url}.\n\n",reset
				# exit 0
			else
				Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).logout()
			end

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end

	end

	

end
