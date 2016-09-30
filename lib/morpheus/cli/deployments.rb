require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Deployments
	include Morpheus::Cli::CliCommand

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
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end


	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus deployments [list,add, update,remove, versions]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				update(args[1..-1])	
			when 'remove'
				remove(args[1..-1])
			when 'versions'
				list_versions(args[1..-1])
			else
				puts "\nUsage: morpheus deployments [list,add, update,remove, versions]\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments list [-s] [-o] [-m]"
			build_common_options(opts, options, [:list, :json, :remote])
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
					puts JSON.pretty_generate(json_response)
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
			print_rest_exception(e, options)
			exit 1
		end
	end

	def list_versions(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments versions [deployment] [-s] [-o] [-m]"
			build_common_options(opts, options, [:list, :json, :remote])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		deployment_name  = args[0]
		connect(options)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			deployment = find_deployment_by_name_or_code_or_id(deployment_name)
			exit 1 if deployment.nil?

			json_response = @deployments_interface.list_versions(deployment['id'],params)
			if options[:json]
					puts JSON.pretty_generate(json_response)
			else
				versions = json_response['versions']
				print "\n" ,cyan, bold, "Morpheus Deployment Versions\n","=============================", reset, "\n\n"
				if versions.empty?
					puts yellow,"No deployment versions currently exist.",reset
				else
					print cyan
					versions_table_data = versions.collect do |version|
						{version: version['userVersion'], type: version['deployType'], updated: format_local_dt(version['lastUpdated'])}
					end
					tp versions_table_data, :version, :type, :updated
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args)
		deployment_name = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments update [deployment] [options]"
			build_common_options(opts, options, [:options, :json, :remote])
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

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{optparse.banner}\n\n"
				option_lines = update_deployment_option_types().collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			deployment_keys = ['name','description']
			changes_payload = (params.select {|k,v| deployment_keys.include?(k) })
			deployment_payload = deployment
			if changes_payload
				deployment_payload.merge!(changes_payload)
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
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		deployment_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments add [name]"
			opts.on( '-d', '--description DESCRIPTION', "Description" ) do |val|
				options[:description] = val
			end
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)

		begin
			payload = {deployment: {name: deployment_name, description: options[:description]}}
			json_response = @deployments_interface.create(payload)
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Deployment #{json_response['deployment']['name']} created successfully", reset, "\n\n"			
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		deployment_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus deployments remove [deployment]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
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
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the deployment #{deployment['name']}?")
				exit
			end
			json_response = @deployments_interface.destroy(deployment['id'])
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Deployment #{deployment['name']} removed", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
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
			print_red_alert "Deployment not found by '#{val}'"
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
			print_red_alert "Deployment Type not found by '#{val}'"
			return nil
		end
		return result
	end

	def update_deployment_option_types()
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 0},
			{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'displayOrder' => 1}
		]
	end
end
