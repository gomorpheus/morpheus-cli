require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::RecentActivityCommand
  include Morpheus::Cli::CliCommand
  
  cli_command_name :'recent-activity'
  cli_command_hidden # remove once this is done

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
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
		"Usage: morpheus recent-activity"
	end

	def handle(args)
		list(args)
	end
	
	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on(nil,'--start', "Start timestamp. Default is 30 days ago.") do |val|
				options[:start_ts] = val
			end
			opts.on(nil,'--end', "End timestamp. Default is now.") do |val|
				options[:end_ts] = val
			end
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse(args)

		connect(options)
		begin
			
			params = {}
			[:phrase, :offset, :max, :sort, :direction, :start, :end].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @dashboard_interface.recent_activity(params)
			
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
