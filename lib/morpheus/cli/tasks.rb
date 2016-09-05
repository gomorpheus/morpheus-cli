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
			puts "\nUsage: morpheus tasks [list,add, update,remove, details, task-types]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				update(args[1..-1])	
			when 'details'
				details(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'task-types'
				task_types(args[1..-1])
			else
				puts "\nUsage: morpheus tasks [list,add, update,remove, details, task-types]\n\n"
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
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error,options)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			exit 1
		end
	end

	def details(args)
				task_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks details [task]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			task = find_task_by_name_or_code_or_id(task_name)

			exit 1 if task.nil?
			task_type = find_task_type_by_name(task['taskType']['name'])
			if options[:json]
					puts JSON.pretty_generate({task:task})
			else
				print "\n", cyan, "Task #{task['name']} - #{task['taskType']['name']}\n\n"
				task_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
					puts "  #{optionType['fieldLabel']} : " + (optionType['type'] == 'password' ? "#{task['taskOptions'][optionType['fieldName']] ? '************' : ''}" : "#{task['taskOptions'][optionType['fieldName']] || optionType['defaultValue']}")
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error,options)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			exit 1
		end
	end

	def update(args)
		task_name = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks update [task] [options]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)

		connect(options)
		
		begin


			task = find_task_by_name_or_code_or_id(task_name)
			exit 1 if task.nil?
			task_type = find_task_type_by_name(task['taskType']['name'])

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{optparse.banner}\n\n"
				option_lines = update_task_option_types(task_type).collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			task_keys = ['name']
			changes_payload = (params.select {|k,v| task_keys.include?(k) })
			task_payload = task
			if changes_payload
				task_payload.merge!(changes_payload)
			end
			puts params
			if params['taskOptions']
				task_payload['taskOptions'].merge!(params['taskOptions'])
			end

			request_payload = {task: task_payload}
			response = @tasks_interface.update(task['id'], request_payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				if !response['success']
					exit 1
				end
			else
				print "\n", cyan, "Task #{response['task']['name']} updated", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			exit 1
		end
	end


	def task_types(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks task-types"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			json_response = @tasks_interface.task_types()
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				task_types = json_response['taskTypes']
				print "\n" ,cyan, bold, "Morpheus Task Types\n","==================", reset, "\n\n"
				if task_types.nil? || task_types.empty?
					puts yellow,"No task types currently exist on this appliance. This could be a seed issue.",reset
				else
					print cyan
					tasks_table_data = task_types.collect do |task_type|
						{name: task_type['name'], id: task_type['id'], code: task_type['code'], description: task_type['description']}
					end
					tp tasks_table_data, :id, :name, :code, :description
				end

				print reset,"\n\n"
			end
			
			
		rescue => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error,options)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			exit 1
		end
	end

	def add(args)
		task_name = args[0]
		task_type_name = nil
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks add [task] -t TASK_TYPE"
			opts.on( '-t', '--type TASK_TYPE', "Task Type" ) do |val|
				task_type_name = val
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)

		if task_type_name.nil?
			puts "Task Type must be specified...\n#{optparse.banner}"
			exit 1
		end
		begin
			task_type = find_task_type_by_name(task_type_name)
			if task_type.nil?
				puts "Task Type not found!"
				exit 1
			end
			input_options = Morpheus::Cli::OptionTypes.prompt(task_type['optionTypes'],options[:options],@api_client, options[:params])
			payload = {task: {name: task_name, taskOptions: input_options['taskOptions'], taskType: {code: task_type['code'], id: task_type['id']}}}
			json_response = @tasks_interface.create(payload)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Task #{json_response['task']['name']} created successfully", reset, "\n\n"			
			end
		rescue RestClient::Exception => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error,options)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			exit 1
		end
	end

	def remove(args)
		task_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks remove [task]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			task = find_task_by_name_or_code_or_id(task_name)
			exit 1 if task.nil?
			exit unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the task #{task['name']}?")
			json_response = @tasks_interface.destroy(task['id'])
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Task #{task['name']} removed", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error,options)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			exit 1
		end
	end


private
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

	def find_task_type_by_name(val)
		raise "find_task_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @tasks_interface.task_types(val)
		result = nil
		if !results['taskTypes'].nil? && !results['taskTypes'].empty?
			result = results['taskTypes'][0]
		elsif val.to_i.to_s == val
			results = @tasks_interface.task_types(val.to_i)
			result = results['taskType']
		end
		if result.nil?
			print red,bold, "\nTask Type not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	def update_task_option_types(task_type)
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 0}
		] + task_type['optionTypes']
	end
end