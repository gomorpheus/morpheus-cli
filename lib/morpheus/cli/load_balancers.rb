# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancers
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
		@load_balancers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).load_balancers
		
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
	end


	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus load-balancers [list,add, update,remove, details, lb-types]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				# update(args[1..-1])	
			when 'details'
				details(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'lb-types'
				lb_types(args[1..-1])
			else
				puts "\nUsage: morpheus load-balancers [list,add, update,remove, details, lb-types]\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus load-balancers list [-s] [-o] [-m]"
			build_common_options(opts, options, [:list, :json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			json_response = @load_balancers_interface.get(params)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				lbs = json_response['loadBalancers']
				print "\n" ,cyan, bold, "Morpheus Load Balancers\n","==================", reset, "\n\n"
				if lbs.empty?
					puts yellow,"No load balancers currently configured.",reset
				else
					print cyan
					lb_table_data = lbs.collect do |lb|
						{name: lb['name'], id: lb['id'], type: lb['type']['name']}
					end
					tp lb_table_data, :id, :name, :type
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

	def details(args)
				lb_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus load-balancers details [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			lb = find_lb_by_name(lb_name)

			exit 1 if lb.nil?
			lb_type = find_lb_type_by_name(lb['type']['name'])
			if options[:json]
					puts JSON.pretty_generate({task:task})
			else
				print "\n", cyan, "Lb #{lb['name']} - #{lb['type']['name']}\n\n"
				lb_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
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
		lb_name = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks update [task] [options]"
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)

		connect(options)
		
		begin


			task = find_task_by_name_or_code_or_id(lb_name)
			exit 1 if task.nil?
			lb_type = find_lb_type_by_name(task['type']['name'])

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{optparse.banner}\n\n"
				option_lines = update_task_option_types(lb_type).collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
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
			response = @load_balancers_interface.update(task['id'], request_payload)
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


	def lb_types(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus load-balancers lb-types"
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			json_response = @load_balancers_interface.load_balancer_types()
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				lb_types = json_response['loadBalancerTypes']
				print "\n" ,cyan, bold, "Morpheus Load Balancer Types\n","============================", reset, "\n\n"
				if lb_types.nil? || lb_types.empty?
					puts yellow,"No lb types currently exist on this appliance. This could be a seed issue.",reset
				else
					print cyan
					lb_table_data = lb_types.collect do |lb_type|
						{name: lb_type['name'], id: lb_type['id'], code: lb_type['code']}
					end
					tp lb_table_data, :id, :name, :code
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
		lb_name = args[0]
		lb_type_name = nil
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus load-balancers add [lb] -t LB_TYPE"
			opts.on( '-t', '--type LB_TYPE', "Lb Type" ) do |val|
				lb_type_name = val
			end
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)

		if lb_type_name.nil?
			puts "LB Type must be specified...\n#{optparse.banner}"
			exit 1
		end

		lb_type = find_lb_type_by_name(lb_type_name)
		if lb_type.nil?
			puts "LB Type not found!"
			exit 1
		end
		input_options = Morpheus::Cli::OptionTypes.prompt(lb_type['optionTypes'],options[:options],@api_client, options[:params])
		payload = {task: {name: lb_name, taskOptions: input_options['taskOptions'], type: {code: lb_type['code'], id: lb_type['id']}}}
		begin
			json_response = @load_balancers_interface.create(payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "LB #{json_response['loadBalancer']['name']} created successfully", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def remove(args)
		lb_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus load-balancers remove [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			lb = find_lb_by_name(lb_name)
			exit 1 if lb.nil?
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the load balancer #{lb['name']}?")
				exit
			end
			json_response = @load_balancers_interface.destroy(lb['id'])
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Load Balancer #{lb['name']} removed", reset, "\n\n"
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
	def find_lb_by_name(val)
		raise "find_lb_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @load_balancers_interface.get(val)
		result = nil
		if !results['loadBalancers'].nil? && !results['loadBalancers'].empty?
			result = results['loadBalancers'][0]
		elsif val.to_i.to_s == val
			results = @load_balancers_interface.get(val.to_i)
			result = results['loadBalancer']
		end
		if result.nil?
			print red,bold, "\nLB not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	def find_lb_type_by_name(val)
		raise "find_lb_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @load_balancers_interface.load_balancer_types(val)
		result = nil
		if !results['loadBalancerTypes'].nil? && !results['loadBalancerTypes'].empty?
			result = results['loadBalancerTypes'][0]
		elsif val.to_i.to_s == val
			results = @load_balancers_interface.load_balancer_types(val.to_i)
			result = results['loadBalancerType']
		end
		if result.nil?
			print red,bold, "\nLB Type not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

end
