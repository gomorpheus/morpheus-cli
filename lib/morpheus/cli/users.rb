# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Users
	include Term::ANSIColor
  include Morpheus::Cli::CliCommand
  
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
		usage = "Usage: morpheus users [list,add,remove, update] [username]"
		if args.empty?
			puts "\n#{usage}\n\n"
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
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		usage = "Usage: morpheus users list [options]"
		options = {}
		params = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |val|
				account_name = val
			end
			
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			# current user account by default
			account = nil
			if !account_name.nil?
				account = find_account_by_name(account_name)
				exit 1 if account.nil?
			end
			account_id = account ? account['id'] : nil

			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			
			json_response = @users_interface.get(account_id, params)
			users = json_response['users']

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Users\n","==================", reset, "\n\n"
				if users.empty?
					puts yellow,"No users found.",reset
				else
					users_table = users.collect do |user|
						{id: user['id'], username: user['username'], first: user['firstName'], last: user['lastName'], email: user['email'], role: user['role'] ? user['role']['authority'] : nil, account: user['account'] ? user['account']['name'] : nil}
					end
					print cyan
					tp users_table, :id, :account, :first, :last, :username, :email, :role
				end
				print reset,"\n\n"
			end
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
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
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |val|
				account_name = val
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)

		connect(options)
		
		begin

			# current user account by default
			account = nil
			if !account_name.nil?
				account = find_account_by_name(account_name)
				exit 1 if account.nil?
			end
			account_id = account ? account['id'] : nil

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options)
			params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious

			#puts "parsed params is : #{params.inspect}"
			user_keys = ['username', 'firstName', 'lastName', 'email', 'password', 'passwordConfirmation']
			user_payload = params.select {|k,v| user_keys.include?(k) }
			if params['role'].to_s != ''
				role = find_role_by_name(account_id, params['role'])
				exit 1 if role.nil?
				user_payload['role'] = {id: role['id']}
			end
			user_payload['instanceLimits'] = {}
			user_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
			user_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
			user_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
			request_payload = {user: user_payload}
			response = @users_interface.create(account_id, request_payload)
			if account
				print "\n", cyan, "User #{user_payload['username']} added to account #{account['name']}", reset, "\n\n"
			else
				print "\n", cyan, "User #{user_payload['username']} added", reset, "\n\n"
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

	def update(args)
		usage = "Usage: morpheus users update [username] [options]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		username = args[0]
		options = {}
		#options['username'] = args[0] if args[0]
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |val|
				account_name = val
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)

		connect(options)
		
		begin

			# current user account by default
			account = nil
			if !account_name.nil?
				account = find_account_by_name(account_name)
				exit 1 if account.nil?
			end
			account_id = account ? account['id'] : nil

			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{usage}\n\n"
				option_lines = update_user_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			user_keys = ['username', 'firstName', 'lastName', 'email', 'password', 'passwordConfirmation']
			user_payload = params.select {|k,v| user_keys.include?(k) }
			if params['role'].to_s != ''
				role = find_role_by_name(account_id, params['role'])
				exit 1 if role.nil?
				user_payload['role'] = {id: role['id']}
			end
			request_payload = {user: user_payload}
			response = @users_interface.update(account_id, user['id'], request_payload)
			print "\n", cyan, "User #{user_payload['username'] || user['username']} updated", reset, "\n\n"
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

	def remove(args)
		usage = "Usage: morpheus users remove [username]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		username = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |val|
				account_name = val
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin

			# current user account by default
			account = nil
			if !account_name.nil?
				account = find_account_by_name(account_name)
				exit 1 if account.nil?
			end

			user = find_user_by_username(account_id, username)
			exit 1 if user.nil?
			exit unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the user #{user['username']}?")
			@users_interface.destroy(account_id, user['id'])
			# list([])
			print "\n", cyan, "User #{username} removed", reset, "\n\n"
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

private

	def find_account_by_id(id)
		raise "find_account_by_id passed a bad id: #{id.inspect}" if id.to_s == ''
		results = @accounts_interface.get(id.to_i)
		if results['account'].empty?
			print red,bold, "\nAccount not found by id '#{id}'\n\n",reset
			return nil
		end
		return results['account']
	end

	def find_user_by_username(account_id, username)
		raise "find_account_by_name passed a bad username: #{username.inspect}" if username.to_s == ''
		results = @users_interface.get(account_id, username.to_s)
		if results['users'].empty?
			print red,bold, "\nUser not found by '#{username}'\n\n",reset
			return nil
		end
		return results['users'][0]
	end

	def find_account_by_name(name)
		raise "find_account_by_name passed a bad name: #{name.inspect}" if name.to_s == ''
		results = @accounts_interface.get(name.to_s)
		if results['accounts'].empty?
			print red,bold, "\nAccount not found by name '#{name}'\n\n",reset
			return nil
		end
		return results['accounts'][0]
	end

	def find_role_by_name(account_id, name)
		raise "find_role_by_name passed a bad name: #{name.inspect}" if name.to_s == ''
		results = @roles_interface.get(account_id, name.to_s)
		if results['roles'].empty?
			print red,bold, "\nRole not found by name '#{name}'\n\n",reset
			return nil
		end
		return results['roles'][0]
	end

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
