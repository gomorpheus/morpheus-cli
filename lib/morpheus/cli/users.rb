# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Users
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
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
	end

	def handle(args)
		usage = "Usage: morpheus users [list,details,add,update,remove] [username]"
		if args.empty?
			puts "\n#{usage}\n\n"
			return
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
			when 'feature-permissions'
				feature_permissions(args[1..-1])
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		usage = "Usage: morpheus users list [options]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:account, :list, :json])
		end
		optparse.parse(args)
		connect(options)
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			
			json_response = @users_interface.list(account_id, params)
			users = json_response['users']

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Users\n","==================", reset, "\n\n"
				if users.empty?
					puts yellow,"No users found.",reset
				else
					print_users_table(users)
					print_results_pagination(json_response)
				end
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
		usage = "Usage: morpheus users details [username] [options]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
      build_common_options(opts, options, [:account, :json])
      opts.on(nil,'--feature-access', "Display Feature Access") do |val|
				options[:include_feature_access] = true
			end
			# opts.on(nil,'--group-access', "Display Group Access") do
			# 	options[:include_group_access] = true
			# end
			# opts.on(nil,'--cloud-access', "Display Cloud Access") do
			# 	options[:include_cloud_access] = true
			# end
			# opts.on(nil,'--instance-type-access', "Display Instance Type Access") do
			# 	options[:include_instance_type_access] = true
			# end
			opts.on(nil,'--all-access', "Display All Access Lists") do
				options[:include_feature_access] = true
				options[:include_group_access] = true
				options[:include_cloud_access] = true
				options[:include_instance_type_access] = true
			end
		end
		optparse.parse(args)

		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		username = args[0]

		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			# todo: users_response = @users_interface.list(account_id, {name: name})
			#       there may be response data outside of user that needs to be displayed
			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?

			# meh, this should just always be returned with GET /api/users/:id
			user_feature_permissions_json = nil
			user_feature_permissions = nil
			if options[:include_feature_access]
				user_feature_permissions_json = @users_interface.feature_permissions(account_id, user['id'])
				user_feature_permissions = user_feature_permissions_json['featurePermissions']
			end

			if options[:json]
				print JSON.pretty_generate({user:user})
				print "\n"
				if (user_feature_permissions_json)
					print JSON.pretty_generate(user_feature_permissions_json)
					print "\n"
				end
			else
				print "\n" ,cyan, bold, "User Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{user['id']}"
				puts "Account: #{user['account'] ? user['account']['name'] : nil}"
				puts "First Name: #{user['firstName']}"
				puts "Last Name: #{user['lastName']}"
				puts "Username: #{user['username']}"
				puts "Email: #{user['email']}"
				puts "Role: #{format_user_role_names(user)}"
				puts "Date Created: #{format_local_dt(user['dateCreated'])}"
				puts "Last Updated: #{format_local_dt(user['lastUpdated'])}"
				print "\n" ,cyan, bold, "User Instance Limits\n","==================", reset, "\n\n"
				print cyan
				puts "Max Storage (bytes): #{user['instanceLimits'] ? user['instanceLimits']['maxStorage'] : 0}"
				puts "Max Memory (bytes): #{user['instanceLimits'] ? user['instanceLimits']['maxMemory'] : 0}"
				puts "CPU Count: #{user['instanceLimits'] ? user['instanceLimits']['maxCpu'] : 0}"

				if options[:include_feature_access] && user_feature_permissions
					if user_feature_permissions
						print "\n" ,cyan, bold, "Feature Permissions\n","==================", reset, "\n\n"
						print cyan
						rows = user_feature_permissions.collect do |code, access|
							{code: code, access: get_access_string(access) }
						end
						tp rows, [:code, :access]
					else
						puts yellow,"No permissions found.",reset
					end
				end

				print cyan
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		usage = "Usage: morpheus users add [options]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:account, :options, :dry_run, :json])
			opts.on('-h', '--help', "Prints this help" ) do
        puts opts
				puts Morpheus::Cli::OptionTypes.display_option_types_help(add_user_option_types)
        exit
      end
		end
		optparse.parse(args)

		connect(options)
		
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			# remove role option_type, it is just for help display, the role prompt is separate down below
			prompt_option_types = add_user_option_types().reject {|it| ['role'].include?(it['fieldName']) }
			
			params = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, options[:options], @api_client, options[:params])

			#puts "parsed params is : #{params.inspect}"
			user_keys = ['username', 'firstName', 'lastName', 'email', 'password', 'passwordConfirmation', 'instanceLimits']
			user_payload = params.select {|k,v| user_keys.include?(k) }
			if !user_payload['instanceLimits']
				user_payload['instanceLimits'] = {}
				user_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
				user_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
				user_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
			end

			roles = prompt_user_roles(account_id, nil, options)
			if !roles.empty?
				user_payload['roles'] = roles.collect {|r| {id: r['id']} }
			end

			request_payload = {user: user_payload}
			json_response = @users_interface.create(account_id, request_payload)

			if options[:dry_run]
				print_dry_run("POST #{@appliance_url}/api/accounts", request_payload)
                                return
                        end
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				if account
					print_green_success "Added user #{user_payload['username']} to account #{account['name']}"
				else
					print_green_success "Added user #{user_payload['username']}"
				end

				details_options = [user_payload["username"]]
				if account
					details_options.push "--account-id", account['id'].to_s
				end
				details(details_options)
			end

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args)
		usage = "Usage: morpheus users update [username] [options]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:account, :options, :json])
			opts.on('-h', '--help', "Prints this help" ) do
        puts opts
				puts Morpheus::Cli::OptionTypes.display_option_types_help(update_user_option_types)
        exit
      end
		end
		optparse.parse(args)

		if args.count < 1
			puts "#{usage}\n\n"
			puts Morpheus::Cli::OptionTypes.display_option_types_help(update_user_option_types)
			exit 1
		end
		username = args[0]

		connect(options)
		
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?

			#params = Morpheus::Cli::OptionTypes.prompt(update_user_option_types, options[:options], @api_client, options[:params])
			params = options[:options] || {}
			roles = prompt_user_roles(account_id, user['id'], options.merge(no_prompt: true))
			if !roles.empty?
				params['roles'] = roles.collect {|r| {id: r['id']} }
			end
			
			if params.empty?
				puts "\n#{usage}\n\n"
				puts Morpheus::Cli::OptionTypes.display_option_types_help(update_user_option_types)
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			user_keys = ['username', 'firstName', 'lastName', 'email', 'password', 'instanceLimits', 'roles']
			user_payload = params.select {|k,v| user_keys.include?(k) }
			if !user_payload['instanceLimits']
				user_payload['instanceLimits'] = {}
				user_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
				user_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
				user_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
			end

			request_payload = {user: user_payload}
			json_response = @users_interface.update(account_id, user['id'], request_payload)
			
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Updated user #{user_payload['username']}"
				details_options = [user_payload["username"] || user['username']]
				if account
					details_options.push "--account-id", account['id'].to_s
				end
				details(details_options)
			end

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		usage = "Usage: morpheus users remove [username]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			build_common_options(opts, options, [:account, :auto_confirm, :json])
		end
		optparse.parse(args)

		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		username = args[0]

		connect(options)
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the user #{user['username']}?")
				exit
			end
			json_response = @users_interface.destroy(account_id, user['id'])

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "User #{username} removed"
				# list([])
			end
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private

	def add_user_option_types
		[
			{'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
			{'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
			{'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'displayOrder' => 3},
			{'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'displayOrder' => 4},
			{'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'displayOrder' => 6},
			{'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'displayOrder' => 7},
			{'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 8},
			{'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 9},
			{'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 10},
			{'fieldName' => 'role', 'fieldLabel' => 'Role', 'type' => 'text', 'displayOrder' => 11, 'description' => "Role names (comma separated)"},
		]
	end

	def update_user_option_types
		[
			{'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
			{'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
			{'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
			{'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => false, 'displayOrder' => 4},
			{'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => false, 'displayOrder' => 6},
			{'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => false, 'displayOrder' => 7},
			{'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 8},
			{'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 9},
			{'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 10},
			{'fieldName' => 'role', 'fieldLabel' => 'Role', 'type' => 'text', 'displayOrder' => 11, 'description' => "Role names (comma separated)"},
		]
	end

	# prompt user to select roles for a new or existing user
	# options['role'] can be passed as comma separated role names
	# if so, it will be used instead of prompting
	# returns array of role objects
	def prompt_user_roles(account_id, user_id, options={})

		passed_role_string = nil
		if options['role'] || (options[:options] && (options[:options]['role'] || options[:options]['roles']))
			passed_role_string = options['role'] || (options[:options] && (options[:options]['role'] || options[:options]['roles']))
		end
		passed_role_names = []
		if !passed_role_string.empty?
			passed_role_names = passed_role_string.split(',').uniq.compact.collect {|r| r.strip}
		end

		available_roles = @users_interface.available_roles(account_id, user_id)['roles']

		if available_roles.empty?
			print_red_alert "No available roles found."
			exit 1
		end
		role_options = available_roles.collect {|role|
			{'name' => role['authority'], 'value' => role['id']}
		}

		# found_roles = []
		roles = []

		if !passed_role_names.empty?
			invalid_role_names = []
			passed_role_names.each do |role_name| 
				found_role = available_roles.find {|ar| ar['authority'] == role_name}
				if found_role
					# found_roles << found_role
					roles << found_role
				else
					invalid_role_names << role_name
				end
			end
			if !invalid_role_names.empty?
				print_red_alert "Invalid Roles: #{invalid_role_names.join(', ')}"
				exit 1
			end
		end

		if roles.empty?
			no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
			if !no_prompt
				v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleId', 'fieldLabel' => 'Role', 'type' => 'select', 'selectOptions' => role_options, 'required' => true}], options[:options])
				role_id = v_prompt['roleId']
				roles << available_roles.find {|r| r['id'].to_i == role_id.to_i }
				add_another_role = true
				while add_another_role do
					v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleId', 'fieldLabel' => 'Another Role', 'type' => 'select', 'selectOptions' => role_options, 'required' => false}], options[:options])
					if v_prompt['roleId'].to_s.empty?
						add_another_role = false
					else
						role_id = v_prompt['roleId']
						roles << available_roles.find {|r| r['id'].to_i == role_id.to_i }
					end
				end
			end
		end

		roles = roles.compact
		return roles

	end

end
