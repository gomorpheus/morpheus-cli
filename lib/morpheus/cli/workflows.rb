# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Workflows
	include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
	end

	def connect(opts)
		if opts[:remote]
			@appliance_url = opts[:remote]
			@appliance_name = opts[:remote]
			@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials(opts)
		else
			@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials(opts)
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)		
		@tasks_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).tasks
		@task_sets_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).task_sets
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
	end


	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus workflows [list,add,remove]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus workflows [list,add,remove]\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus workflows list [-s] [-o] [-m]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			params = {}
			if options[:offset]
				params[:offset] = options[:offset]
			end
			if options[:max]
				params[:max] = options[:max]
			end
			if options[:phrase]
				params[:phrase] = options[:phrase]
			end
			json_response = @task_sets_interface.get(params)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				task_sets = json_response['taskSets']
				print "\n" ,cyan, bold, "Morpheus Workflows\n","==================", reset, "\n\n"
				if task_sets.empty?
					puts yellow,"No workflows currently configured.",reset
				else
					print cyan
					tasks_table_data = task_sets.collect do |task_set|
						{name: task_set['name'], id: task_set['id']}
					end
					tp tasks_table_data, :id, :name
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def add(args)
	end

	def remove(args)
	end
end