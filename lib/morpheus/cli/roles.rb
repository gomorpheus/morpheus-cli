# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Roles
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		#@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
		@whoami_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).whoami
		@users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
		@accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
		@roles_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).roles
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
		#@clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types

	end

	def handle(args)
		usage = "Usage: morpheus roles [list,details,add,update,remove,update-feature-access,update-global-group-access,update-group-access,update-global-cloud-access,update-cloud-access,update-global-instance-type-access,update-instance-type-access] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
			exit 1
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'details'
				details(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				update(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'update-feature-access'
				update_feature_access(args[1..-1])
			when 'update-global-group-access'
				update_global_group_access(args[1..-1])
			when 'update-group-access'
				update_group_access(args[1..-1])
			when 'update-global-cloud-access'
				update_global_cloud_access(args[1..-1])
			when 'update-cloud-access'
				update_cloud_access(args[1..-1])
			when 'update-global-instance-type-access'
				update_global_instance_type_access(args[1..-1])
			when 'update-instance-type-access'
				update_instance_type_access(args[1..-1])
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		usage = "Usage: morpheus roles list"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse(args)

		connect(options)
		begin
			
			load_whoami()

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
			
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			
			json_response = @roles_interface.list(account_id, params)
			roles = json_response['roles']
			
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Roles\n","==================", reset, "\n\n"
				if roles.empty?
					puts yellow,"No roles found.",reset
				else
					print_roles_table(roles, {is_master_account: @is_master_account})
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
		usage = "Usage: morpheus roles details [name]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on(nil,'--feature-access', "Display Feature Access") do |val|
				options[:include_feature_access] = true
			end
			opts.on(nil,'--group-access', "Display Group Access") do
				options[:include_group_access] = true
			end
			opts.on(nil,'--cloud-access', "Display Cloud Access") do
				options[:include_cloud_access] = true
			end
			opts.on(nil,'--instance-type-access', "Display Instance Type Access") do
				options[:include_instance_type_access] = true
			end
			opts.on(nil,'--all-access', "Display All Access Lists") do
				options[:include_feature_access] = true
				options[:include_group_access] = true
				options[:include_cloud_access] = true
				options[:include_instance_type_access] = true
			end
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			json_response = @roles_interface.get(account_id, role['id'])
			role = json_response['role']

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Role Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{role['id']}"
				puts "Name: #{role['authority']}"
				puts "Description: #{role['description']}"
				puts "Scope: #{role['scope']}"
				puts "Type: #{format_role_type(role)}"
				puts "Multitenant: #{role['multitenant'] ? 'Yes' : 'No'}"
				puts "Owner: #{role['owner'] ? role['owner']['name'] : nil}"
				puts "Date Created: #{format_local_dt(role['dateCreated'])}"
				puts "Last Updated: #{format_local_dt(role['lastUpdated'])}"

				print "\n" ,cyan, bold, "Role Instance Limits\n","==================", reset, "\n\n"
				print cyan
				puts "Max Storage (bytes): #{role['instanceLimits'] ? role['instanceLimits']['maxStorage'] : 0}"
				puts "Max Memory (bytes): #{role['instanceLimits'] ? role['instanceLimits']['maxMemory'] : 0}"
				puts "CPU Count: #{role['instanceLimits'] ? role['instanceLimits']['maxCpu'] : 0}"

				print "\n" ,cyan, bold, "Feature Access\n","==================", reset, "\n\n"
				print cyan

				if options[:include_feature_access]
					rows = json_response['featurePermissions'].collect do |it|
			      {
			      	code: it['code'], 
			        name: it['name'], 
			        access: get_access_string(it['access']), 
			      }
			    end
			    tp rows, [:code, :name, :access]
			  else
			  	puts "Use --feature-access to list feature access"
			  end

		    print "\n" ,cyan, bold, "Group Access\n","==================", reset, "\n\n"
				print cyan
				
				puts "Global Group Access: #{get_access_string(json_response['globalSiteAccess'])}\n\n"
				if json_response['globalSiteAccess'] == 'custom'
					if options[:include_group_access]
						rows = json_response['sites'].collect do |it|
				      {
				        name: it['name'], 
				        access: get_access_string(it['access']), 
				      }
				    end
				    tp rows, [:name, :access]
					else
						puts "Use --group-access to list custom access"
					end
				end

				print "\n" ,cyan, bold, "Cloud Access\n","==================", reset, "\n\n"
				print cyan
				
				puts "Global Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}\n\n"
				if json_response['globalZoneAccess'] == 'custom'
					if options[:include_cloud_access]
						rows = json_response['zones'].collect do |it|
				      {
				        name: it['name'], 
				        access: get_access_string(it['access']), 
				      }
				    end
				    tp rows, [:name, :access]
					else
						puts "Use --cloud-access to list custom access"
					end
				end

				print "\n" ,cyan, bold, "Instance Type Access\n","==================", reset, "\n\n"
				print cyan
				
				puts "Global Instance Type Access: #{get_access_string(json_response['globalInstanceTypeAccess'])}\n\n"
				if json_response['globalInstanceTypeAccess'] == 'custom'
					if options[:include_instance_type_access]
						rows = json_response['instanceTypePermissions'].collect do |it|
				      {
				        name: it['name'], 
				        access: get_access_string(it['access']), 
				      }
				    end
				    tp rows, [:name, :access]
					else
						puts "Use --instance-type-access to list custom access"
					end
				end

				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		usage = "Usage: morpheus roles add [options]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:options, :json])
		end
		optparse.parse(args)

		connect(options)
		begin

			load_whoami()
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			# argh, some options depend on others here...eg. multitenant is only available when roleType == 'user'
			#prompt_option_types = update_role_option_types()

			role_payload = {}
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1}], options[:options])
			role_payload['authority'] = v_prompt['authority']
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2}], options[:options])
			role_payload['description'] = v_prompt['description']

			if @is_master_account
				v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => role_type_options, 'defaultValue' => 'user', 'displayOrder' => 3}], options[:options])
				role_payload['roleType'] = v_prompt['roleType']
			else
				role_payload['roleType'] = 'user'
			end

			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text', 'displayOrder' => 4}], options[:options])
			if v_prompt['baseRole'].to_s != ''
				base_role = find_role_by_name(account_id, v_prompt['baseRole'])
				exit 1 if base_role.nil?
				role_payload['baseRoleId'] = base_role['id']
			end

			if @is_master_account
				if role_payload['roleType'] == 'user'
					v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5}], options[:options])
					role_payload['multitenant'] = ['on','true'].include?(v_prompt['multitenant'].to_s)
				end
			end

			role_payload['instanceLimits'] = {}
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 8}], options[:options])
			if v_prompt['instanceLimits.maxStorage'].to_s.strip != ''
				role_payload['instanceLimits']['maxStorage'] = v_prompt['instanceLimits.maxStorage'].to_i
			end
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 9}], options[:options])
			if v_prompt['instanceLimits.maxMemory'].to_s.strip != ''
				role_payload['instanceLimits']['maxMemory'] = v_prompt['instanceLimits.maxMemory'].to_i
			end
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 10}], options[:options])
			if v_prompt['instanceLimits.maxCpu'].to_s.strip != ''
				role_payload['instanceLimits']['maxCpu'] = v_prompt['instanceLimits.maxCpu'].to_i
			end

			request_payload = {role: role_payload}
			response = @roles_interface.create(account_id, request_payload)

			if account
				print_green_success "Added role #{role_payload['authority']} to account #{account['name']}"
			else
				print_green_success "Added role #{role_payload['authority']}"
			end

			details_options = [role_payload["authority"]]
			if account
				details_options.push "--account-id", account['id'].to_s
			end
			details(details_options)

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args)
		usage = "Usage: morpheus roles update [name] [options]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:options, :json])
		end
		optparse.parse(args)

		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]

		connect(options)
		
		begin

			load_whoami()

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			prompt_option_types = update_role_option_types()
			if !@is_master_account
				prompt_option_types = prompt_option_types.reject {|it| ['roleType', 'multitenant'].include?(it['fieldName']) }
			end
			if role['roleType'] != 'user'
				prompt_option_types = prompt_option_types.reject {|it| ['multitenant'].include?(it['fieldName']) }
			end
			#params = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, options[:options], @api_client, options[:params])
			params = options[:options] || {}

			if params.empty?
				puts "\n#{usage}\n\n"
				option_lines = prompt_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			role_keys = ['authority', 'description', 'instanceLimits']
			role_payload = params.select {|k,v| role_keys.include?(k) }
			if !role_payload['instanceLimits']
				role_payload['instanceLimits'] = {}
				role_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
				role_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
				role_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
			end

			if params['multitenant'].to_s != ''
				role_payload['multitenant'] = ['on','true'].include?(v_prompt['multitenant'].to_s)
			end
			request_payload = {role: role_payload}
			response = @roles_interface.update(account_id, role['id'], request_payload)
			
			print_green_success "Updated role #{role_payload['authority']}"

			details_options = [role_payload["authority"] || role['authority']]
			if account
				details_options.push "--account-id", account['id'].to_s
			end
			details(details_options)

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		usage = "Usage: morpheus roles remove [name]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:auto_confirm, :json])
		end
		optparse.parse(args)
		
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]

		connect(options)
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the role #{role['authority']}?")
				exit
			end
			json_response = @roles_interface.destroy(account_id, role['id'])
			
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} removed"
			end
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_feature_access(args)
		usage = "Usage: morpheus roles update-feature-access [name] [code] [full|read|custom|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 3
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		permission_code = args[1]
		access_value = args[2].to_s.downcase
		if !['full', 'read', 'custom', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			params = {permissionCode: permission_code, access: access_value}
			json_response = @roles_interface.update_permission(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} feature access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_global_group_access(args)
		usage = "Usage: morpheus roles update-global-group-access [name] [full|read|custom|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		access_value = args[1].to_s.downcase
		if !['full', 'read', 'custom', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			params = {permissionCode: 'ComputeSite', access: access_value}
			json_response = @roles_interface.update_permission(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} global group access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_group_access(args)
		usage = "Usage: morpheus roles update-group-access [name] [group_name] [full|read|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		group_name = args[1]
		access_value = args[2].to_s.downcase
		if !['full', 'read', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			role_json = @roles_interface.get(account_id, role['id'])
			
			if role_json['globalSiteAccess'] != 'custom'
				print "\n", red, "Global Group Access is currently: #{role_json['globalSiteAccess'].capitalize}"
				print "\n", "You must first set it to Custom via `morpheus roles update-global-group-access \"#{name}\" custom`"
				print "\n\n", reset
				exit 1
			end

			# group_id = find_group_id_by_name(group_name)
			# exit 1 if group_id.nil?
			group = find_group_by_name(group_name)
			exit 1 if group.nil?
			group_id = group['id']

			params = {groupId: group_id, access: access_value}
			json_response = @roles_interface.update_group(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} global group access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_global_cloud_access(args)
		usage = "Usage: morpheus roles update-global-cloud-access [name] [full|custom|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		access_value = args[1].to_s.downcase
		if !['full', 'custom', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			params = {permissionCode: 'ComputeZone', access: access_value}
			json_response = @roles_interface.update_permission(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} global cloud access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_cloud_access(args)
		usage = "Usage: morpheus roles update-cloud-access [name] [cloud_name] [full|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-g', '--group GROUP', "Group to find cloud in" ) do |val|
				options[:group] = val
			end
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		cloud_name = args[1]
		access_value = args[2].to_s.downcase
		if !['full', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			role_json = @roles_interface.get(account_id, role['id'])
			
			if role_json['globalZoneAccess'] != 'custom'
				print "\n", red, "Global Cloud Access is currently: #{role_json['globalZoneAccess'].capitalize}"
				print "\n", "You must first set it to Custom via `morpheus roles update-global-cloud-access \"#{name}\" custom`"
				print "\n\n", reset
				exit 1
			end

			group_id = nil
			if !options[:group].nil?
				group_id = find_group_id_by_name(options[:group])
			else
				group_id = @active_groups[@appliance_name.to_sym]	
			end

			if group_id.nil?
				print_red_alert "Group not found or specified!"
				exit 1
			end

			cloud_id = find_cloud_id_by_name(group_id, cloud_name)
			exit 1 if cloud_id.nil?
			params = {cloudId: cloud_id, access: access_value}
			json_response = @roles_interface.update_cloud(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} global cloud access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_global_instance_type_access(args)
		usage = "Usage: morpheus roles update-global-instance-type-access [name] [full|custom|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		access_value = args[1].to_s.downcase
		if !['full', 'custom', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end


		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			params = {permissionCode: 'InstanceType', access: access_value}
			json_response = @roles_interface.update_permission(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} global instance type access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update_instance_type_access(args)
		usage = "Usage: morpheus roles update-instance-type-access [name] [instance_type_name] [full|none]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		instance_type_name = args[1]
		access_value = args[2].to_s.downcase
		if !['full', 'none'].include?(access_value)
			puts "\n#{usage}\n\n"
			exit 1
		end

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			role_json = @roles_interface.get(account_id, role['id'])
			
			if role_json['globalInstanceTypeAccess'] != 'custom'
				print "\n", red, "Global Instance Type Access is currently: #{role_json['globalInstanceTypeAccess'].capitalize}"
				print "\n", "You must first set it to Custom via `morpheus roles update-global-instance-type-access \"#{name}\" custom`"
				print "\n\n", reset
				exit 1
			end

			instance_type = find_instance_type_by_name(instance_type_name)
			exit 1 if instance_type.nil?

			params = {instanceTypeId: instance_type['id'], access: access_value}
			json_response = @roles_interface.update_instance_type(account_id, role['id'], params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Role #{role['authority']} global instance type access updated"
			end
				
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private
	
	# def get_access_string(val)
	# 	val ||= 'none'
	# 	if val == 'none'
	# 		"#{white}#{val.to_s.capitalize}#{cyan}"
	# 	else
	# 		"#{green}#{val.to_s.capitalize}#{cyan}"
	# 	end
	# end

	def add_role_option_types
		[
			{'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
			{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
			{'fieldName' => 'roleType', 'fieldLabel' => 'Role Type', 'type' => 'select', 'selectOptions' => [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}], 'defaultValue' => 'user', 'displayOrder' => 3},
			{'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text', 'displayOrder' => 4},
			{'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5},
			{'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 8},
			{'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 9},
			{'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 10},
		]
	end

	"A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use"
	def update_role_option_types
		add_role_option_types.reject {|it| ['roleType', 'baseRole'].include?(it['fieldName']) }
	end


	def find_group_by_name(name)
		group_results = @groups_interface.get(name)
		if group_results['groups'].empty?
			print_red_alert "Group not found by name #{name}"
			return nil
		end
		return group_results['groups'][0]
	end

	# no worky, returning  {"success"=>true, "data"=>[]}
	# def find_group_id_by_name(name)
	# 	option_results = @options_interface.options_for_source('groups',{})
	# 	puts "option_results: #{option_results.inspect}"
	# 	match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
	# 	if match.nil?
	# 		print_red_alert "Group not found by name #{name}"
	# 		return nil
	# 	else
	# 		return match['value']
	# 	end
	# end

	def find_cloud_id_by_name(group_id, name)
		option_results = @options_interface.options_for_source('clouds', {groupId: group_id})
		match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
		if match.nil?
			print_red_alert "Cloud not found by name #{name}"
			return nil
		else
			return match['value']
		end
	end

	def find_instance_type_by_name(name)
		results = @instance_types_interface.get({name: name})
		if results['instanceTypes'].empty?
			print_red_alert "Instance Type not found by name #{name}"
			return nil
		end
		return results['instanceTypes'][0]
	end

	def load_whoami
		whoami_response = @whoami_interface.get()
		@current_user = whoami_response["user"] 
		if @current_user.empty?
			print_red_alert "Unauthenticated. Please login."
			exit 1
		end
		@is_master_account = whoami_response["isMasterAccount"]
	end

	def role_type_options
		[{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}]
	end

end
