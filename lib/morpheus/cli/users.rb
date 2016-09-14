# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Users
	include Term::ANSIColor
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		#@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
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
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		usage = "Usage: morpheus users list [options]"
		options = {}
		params = {}
		account = nil
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.accountScopeOptions(opts,options)
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

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
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def details(args)
		usage = "Usage: morpheus users details [username] [options]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		account = nil
		username = args[0]
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
      Morpheus::Cli::CliCommand.accountScopeOptions(opts,options)
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			
			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil
	
			# todo: users_response = @users_interface.list(account_id, {name: name})
			#       there may be response data outside of user that needs to be displayed
			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?

			if options[:json]
				print JSON.pretty_generate({user:user})
				print "\n"
			else
				print "\n" ,cyan, bold, "User Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{user['id']}"
				puts "Account: #{user['account'] ? user['account']['name'] : nil}"
				puts "First Name: #{user['firstName']}"
				puts "Last Name: #{user['firstName']}"
				puts "Username: #{user['username']}"
				puts "Role: #{user['role'] ? user['role']['authority'] : nil}"
				puts "Date Created: #{format_local_dt(user['dateCreated'])}"
				puts "Last Updated: #{format_local_dt(user['lastUpdated'])}"
				print "\n" ,cyan, bold, "User Instance Limits\n","==================", reset, "\n\n"
				print cyan
				puts "Max Storage (bytes): #{user['instanceLimits'] ? user['instanceLimits']['maxStorage'] : 0}"
				puts "Max Memory (bytes): #{user['instanceLimits'] ? user['instanceLimits']['maxMemory'] : 0}"
				puts "CPU Count: #{user['instanceLimits'] ? user['instanceLimits']['maxCpu'] : 0}"
				print cyan
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def add(args)
		usage = "Usage: morpheus users add [options]"
		# if args.count > 0
		# 	puts "\#{usage}\n\n"
		# 	exit 1
		# end
		options = {}
		#options['username'] = args[0] if args[0]
		account = nil
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.accountScopeOptions(opts,options)
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)

		connect(options)
		
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options)
			params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious

			#puts "parsed params is : #{params.inspect}"
			user_keys = ['username', 'firstName', 'lastName', 'email', 'password', 'passwordConfirmation', 'instanceLimits']
			user_payload = params.select {|k,v| user_keys.include?(k) }
			if params['role'].to_s != ''
				role = find_role_by_name(account_id, params['role'])
				exit 1 if role.nil?
				user_payload['role'] = {id: role['id']}
			end
			request_payload = {user: user_payload}
			response = @users_interface.create(account_id, request_payload)

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

		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def update(args)
		usage = "Usage: morpheus users update [username] [options]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		account = nil
		username = args[0]
		options = {}
		#options['username'] = args[0] if args[0]
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.accountScopeOptions(opts,options)
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)

		connect(options)
		
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{usage}\n"
				option_lines = update_user_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			user_keys = ['username', 'firstName', 'lastName', 'email', 'password', 'instanceLimits']
			user_payload = params.select {|k,v| user_keys.include?(k) }
			if params['role'].to_s != ''
				role = find_role_by_name(account_id, params['role'])
				exit 1 if role.nil?
				user_payload['role'] = {id: role['id']}
			end
			request_payload = {user: user_payload}
			response = @users_interface.update(account_id, user['id'], request_payload)
			
			print_green_success "Updated user #{user_payload['username']}"

			details_options = [user_payload["username"] || user['username']]
			if account
				details_options.push "--account-id", account['id'].to_s
			end
			details(details_options)

		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def remove(args)
		usage = "Usage: morpheus users remove [username]"
		if args.count < 1
			puts "\n#{usage}\n"
			exit 1
		end
		account = nil
		username = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.accountScopeOptions(opts,options)
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin

			account = find_account_from_options(options)
			account_id = account ? account['id'] : nil

			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?
			exit unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the user #{user['username']}?")
			@users_interface.destroy(account_id, user['id'])
			# list([])
			print "\n", cyan, "User #{username} removed", reset, "\n\n"
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

private

	def add_user_option_types
		[
			{'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
			{'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
			{'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => true, 'displayOrder' => 3},
			{'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'displayOrder' => 4},
			{'fieldName' => 'role', 'fieldLabel' => 'Role', 'type' => 'text', 'displayOrder' => 5},
			{'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'displayOrder' => 6},
			{'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'displayOrder' => 7},
			{'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 8},
			{'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 9},
			{'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 10},
		]
	end

	def update_user_option_types
		add_user_option_types.reject {|it| ['passwordConfirmation'].include?(it['fieldName']) }
	end

end
