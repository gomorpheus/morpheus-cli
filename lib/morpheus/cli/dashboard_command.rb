require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::DashboardCommand
	include Morpheus::Cli::CliCommand
		set_command_name :dashboard
	set_command_hidden # remove once this is done

	def initialize() 
		# @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@api_client = establish_remote_appliance_connection(opts)
		@dashboard_interface = @api_client.dashboard
	end

	def usage
		"Usage: morpheus #{command_name}"
	end

	def handle(args)
		show(args)
	end
		def show(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json, :dry_run]) # todo: support :account
		end
		optparse.parse!(args)

		connect(options)
		begin
						params = {}
			if options[:dry_run]
				print_dry_run @dashboard_interface.dry.get(params)
				return
			end
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
