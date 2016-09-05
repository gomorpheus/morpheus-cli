# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Deployments
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
		@deployments_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).deployments
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
	end


	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus deployments [list,add, update,remove, details]\n\n"
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
			else
				puts "\nUsage: morpheus deployments [list,add, update,remove, details, deployment-types]\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments list [-s] [-o] [-m]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			json_response = @deployments_interface.get(params)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				deployments = json_response['deployments']
				print "\n" ,cyan, bold, "Morpheus Deployments\n","====================", reset, "\n\n"
				if deployments.empty?
					puts yellow,"No deployments currently configured.",reset
				else
					print cyan
					deployments_table_data = deployments.collect do |deployment|
						{name: deployment['name'], id: deployment['id'], description: deployment['description'], updated: format_local_dt(deployment['lastUpdated'])}
					end
					tp deployments_table_data, :id, :name, :description, :updated
				end
				print reset,"\n\n"
			end
			
			
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def details(args)
				deployment_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments details [deployment]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			deployment = find_deployment_by_name_or_code_or_id(deployment_name)

			exit 1 if deployment.nil?
			deployment_type = find_deployment_type_by_name(deployment['deploymentType']['name'])
			if options[:json]
					puts JSON.pretty_generate({deployment:deployment})
			else
				print "\n", cyan, "Deployment #{deployment['name']} - #{deployment['deploymentType']['name']}\n\n"
				deployment_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
					puts "  #{optionType['fieldLabel']} : " + (optionType['type'] == 'password' ? "#{deployment['deploymentOptions'][optionType['fieldName']] ? '************' : ''}" : "#{deployment['deploymentOptions'][optionType['fieldName']] || optionType['defaultValue']}")
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
		deployment_name = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments update [deployment] [options]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)

		connect(options)
		
		begin


			deployment = find_deployment_by_name_or_code_or_id(deployment_name)
			exit 1 if deployment.nil?
			deployment_type = find_deployment_type_by_name(deployment['deploymentType']['name'])

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{optparse.banner}\n\n"
				option_lines = update_deployment_option_types(deployment_type).collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			deployment_keys = ['name']
			changes_payload = (params.select {|k,v| deployment_keys.include?(k) })
			deployment_payload = deployment
			if changes_payload
				deployment_payload.merge!(changes_payload)
			end
			puts params
			if params['deploymentOptions']
				deployment_payload['deploymentOptions'].merge!(params['deploymentOptions'])
			end

			request_payload = {deployment: deployment_payload}
			response = @deployments_interface.update(deployment['id'], request_payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				if !response['success']
					exit 1
				end
			else
				print "\n", cyan, "Deployment #{response['deployment']['name']} updated", reset, "\n\n"
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

	def add(args)
		deployment_name = args[0]
		deployment_type_name = nil
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments add [name]"
			opts.on( '-t', '--type TASK_TYPE', "Deployment Type" ) do |val|
				deployment_type_name = val
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)

		if deployment_type_name.nil?
			puts "Deployment Type must be specified...\n#{optparse.banner}"
			exit 1
		end
		begin
			deployment_type = find_deployment_type_by_name(deployment_type_name)
			if deployment_type.nil?
				puts "Deployment Type not found!"
				exit 1
			end
			input_options = Morpheus::Cli::OptionTypes.prompt(deployment_type['optionTypes'],options[:options],@api_client, options[:params])
			payload = {deployment: {name: deployment_name, deploymentOptions: input_options['deploymentOptions'], deploymentType: {code: deployment_type['code'], id: deployment_type['id']}}}
			json_response = @deployments_interface.create(payload)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Deployment #{json_response['deployment']['name']} created successfully", reset, "\n\n"			
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
		deployment_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments remove [deployment]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			deployment = find_deployment_by_name_or_code_or_id(deployment_name)
			exit 1 if deployment.nil?
			exit unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the deployment #{deployment['name']}?")
			json_response = @deployments_interface.destroy(deployment['id'])
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Deployment #{deployment['name']} removed", reset, "\n\n"
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
	def find_deployment_by_name_or_code_or_id(val)
		raise "find_deployment_by_name_or_code_or_id passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @deployments_interface.get(val)
		result = nil
		if !results['deployments'].nil? && !results['deployments'].empty?
			result = results['deployments'][0]
		elsif val.to_i.to_s == val
			results = @deployments_interface.get(val.to_i)
			result = results['deployment']
		end
		if result.nil?
			print red,bold, "\nDeployment not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	def find_deployment_type_by_name(val)
		raise "find_deployment_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @deployments_interface.deployment_types(val)
		result = nil
		if !results['deploymentTypes'].nil? && !results['deploymentTypes'].empty?
			result = results['deploymentTypes'][0]
		elsif val.to_i.to_s == val
			results = @deployments_interface.deployment_types(val.to_i)
			result = results['deploymentType']
		end
		if result.nil?
			print red,bold, "\nDeployment Type not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	def update_deployment_option_types(deployment_type)
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 0}
		] + deployment_type['optionTypes']
	end
end