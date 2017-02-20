# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Workflows
	include Morpheus::Cli::CliCommand

	register_subcommands :list, :add, :update, :remove

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
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end


	def handle(args)
		handle_subcommand(args)
	end


	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			build_common_options(opts, options, [:list, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		connect(options)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			if options[:dry_run]
				print_dry_run @task_sets_interface.dry.get(params)
				return
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
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		workflow_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] --tasks x,y,z")
			opts.on("--tasks x,y,z", Array, "List of tasks to run in order") do |list|
				options[:task_names]= list
			end
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 1 || options[:task_names].empty?
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			tasks = []
			options[:task_names].each do |task_name|
				tasks << find_task_by_name_or_code_or_id(task_name)['id']
			end

			payload = {taskSet: {name: workflow_name, tasks: tasks}}
			if options[:dry_run]
				print_dry_run @task_sets_interface.dry.create(payload)
				return
			end
			json_response = @task_sets_interface.create(payload)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Workflow #{json_response['taskSet']['name']} created successfully", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args) 
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus workflows remove [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		workflow_name = args[0]
		connect(options)
		begin
			workflow = find_workflow_by_name_or_code_or_id(workflow_name)
			exit 1 if workflow.nil?
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the workflow #{workflow['name']}?")
				exit 1
			end
			if options[:dry_run]
				print_dry_run @task_sets_interface.dry.destroy(task['id'])
				return
			end
			json_response = @tasks_interface.destroy(task['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
			elsif !options[:quiet]
				print "\n", cyan, "Workflow #{workflow['name']} removed", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end


private
	def find_workflow_by_name_or_code_or_id(val)
		raise "find_workflow_by_name_or_code_or_id passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @task_sets_interface.get(val)
		result = nil
		if !results['taskSets'].nil? && !results['taskSets'].empty?
			result = results['taskSets'][0]
		elsif val.to_i.to_s == val
			results = @task_sets_interface.get(val.to_i)
			result = results['taskSet']
		end
		if result.nil?
			print red,bold, "\nWorkflow not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	def find_task_by_name_or_code_or_id(val)
		raise "find_task_by_name_or_code_or_id passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @tasks_interface.get(val)
		result = nil
		if !results['tasks'].nil? && !results['tasks'].empty?
			result = results['tasks'][0]
		elsif val.to_i.to_s == val
			results = @tasks_interface.get(val.to_i)
			result = results['task']
		end
		if result.nil?
			print red,bold, "\nTask not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end
end
