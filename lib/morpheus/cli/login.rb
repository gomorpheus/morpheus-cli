# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::Login
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
		"Usage: morpheus login"
	end

	def handle(args)
		login(args)
	end
		# def login
	# 	Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login()	
	# end

	def login(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json]) # todo: support :remote too perhaps
		end
		optparse.parse!(args)

		connect(options)

		begin
						Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(options)

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end

	end

	
end
