require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::DashboardCommand
  include Morpheus::Cli::CliCommand
  
  set_command_name :dashboard
  set_command_hidden # remove once this is done

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).load_saved_credentials()
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
		@dashboard_interface = @api_client.dashboard
	end

	def usage
		"Usage: morpheus dashboard"
	end

	def handle(args)
		show(args)
	end
	
	def show(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json]) # todo: support :account
		end
		optparse.parse(args)

		connect(options)
		begin
			
			params = {}

			json_response = @dashboard_interface.get(params)
			
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				

				# todo: impersonate command and show that info here

				print "\n" ,cyan, bold, "Dashboard\n","==================", reset, "\n\n"
				print cyan
				
				print "\n"
				puts "Coming soon.... see --json"
				print "\n"

				print reset,"\n"

			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end
	

end
