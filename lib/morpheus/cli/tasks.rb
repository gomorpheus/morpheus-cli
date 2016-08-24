# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Tasks
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
			puts "\nUsage: morpheus tasks [list,add,remove]\n\n"
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
				puts "\nUsage: morpheus tasks [list,add,remove]\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks list [-s] [-o] [-m]"
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
			json_response = @tasks_interface.get(params)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				tasks = json_response['tasks']
				print "\n" ,cyan, bold, "Morpheus Tasks\n","==================", reset, "\n\n"
				if tasks.empty?
					puts yellow,"No tasks currently configured.",reset
				else
					print cyan
					tasks_table_data = tasks.collect do |task|
						{name: task['name'], id: task['id'], type: task['taskType']['name']}
					end
					tp tasks_table_data, :id, :name, :type
				end

				print reset,"\n\n"
			end
			
			
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

	def add(args)
	end

	def remove(args)

	end
end