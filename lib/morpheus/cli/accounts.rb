# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Accounts
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
		usage = "Usage: morpheus accounts [list,add,update,remove] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
			exit 1
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
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @accounts_interface.get(params)
			accounts = json_response['accounts']
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Accounts\n","==================", reset, "\n\n"
				if accounts.empty?
					puts yellow,"No accounts found.",reset
				else

					accounts_table = accounts.collect do |account|
						status_state = nil
						if account['active']
							status_state = "#{green}ACTIVE#{cyan}"
						else
							status_state = "#{red}INACTIVE#{cyan}"
						end
						{
							id: account['id'], 
							name: account['name'], 
							description: account['description'], 
							role: account['role'] ? account['role']['authority'] : nil, 
							status: status_state,
							dateCreated: format_local_dt(account['dateCreated']) 
						}
					end
					print cyan
					tp accounts_table, [
						:id, 
						:name, 
						:description, 
						:role, 
						{:dateCreated => {:display_name => "Date Created"} },
						:status
					]
				end
				print reset,"\n\n"
			end
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			exit 1
		end
	end

	def add(args)
		# if args.count > 0
		# 	puts "\nUsage: morpheus hosts add [options]\n\n"
		# 	exit 1
		# end
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus users add [options]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)

		connect(options)
		
		begin

			params = Morpheus::Cli::OptionTypes.prompt(add_account_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious

			#puts "parsed params is : #{params.inspect}"
			account_keys = ['name', 'description', 'currency']
			account_payload = params.select {|k,v| account_keys.include?(k) }
			account_payload['currency'] = account_payload['currency'].to_s.empty? ? "USD" : account_payload['currency'].upcase
			account_payload['instanceLimits'] = {}
			account_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
			account_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
			account_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
			if params['role'].to_s != ''
				role = find_role_by_name(nil, params['role'])
				exit 1 if role.nil?
				account_payload['role'] = {id: role['id']}
			end
			request_payload = {account: account_payload}
			response = @accounts_interface.create(request_payload)
			print "\n", cyan, "Account #{account_payload['name']} added", reset, "\n\n"
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
		usage = "Usage: morpheus hosts update [username] [options]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)

		connect(options)
		
		begin

			account = ((name.to_s =~ /\A\d{1,}\Z/) ? find_account_by_id(name) : find_account_by_name(name) )
			exit 1 if account.nil?

			#params = Morpheus::Cli::OptionTypes.prompt(update_account_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\nUsage: morpheus hosts update [username] [-O firstName=\"William\", etc]\n\n"
				option_lines = update_account_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			account_keys = ['name', 'description', 'currency']
			account_payload = params.select {|k,v| account_keys.include?(k) }
			account_payload['currency'] = account_payload['currency'].upcase unless account_payload['currency'].to_s.empty?
			account_payload['instanceLimits'] = {}
			account_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
			account_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
			account_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
			if params['role'].to_s != ''
				role = find_role_by_name(nil, params['role'])
				exit 1 if role.nil?
				account_payload['role'] = {id: role['id']}
			end
			request_payload = {account: account_payload}
			response = @accounts_interface.update(account['id'], request_payload)
			print "\n", cyan, "Account #{account_payload['name'] || account['name']} updated", reset, "\n\n"
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
		usage = "Usage: morpheus accounts remove [name]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			# allow finding by ID since name is not unique!
			account = ((name.to_s =~ /\A\d{1,}\Z/) ? find_account_by_id(name) : find_account_by_name(name) )
			exit 1 if account.nil?
			exit unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the account #{account['name']}?")
			@accounts_interface.destroy(account['id'])
			# list([])
			print "\n", cyan, "Account #{account['name']} removed", reset, "\n\n"
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

	def find_account_by_name(name)
		raise "find_account_by_name passed a bad name: #{name.inspect}" if name.to_s == ''
		results = @accounts_interface.get(name)
		if results['accounts'].empty?
			print red,bold, "\nAccount not found by name '#{name}'\n\n",reset
			return nil
		end
		return results['accounts'][0]
	end

	def find_role_by_name(account_id, name)
		raise "find_role_by_name passed a bad name: #{name.inspect}" if name.to_s == ''
		results = @roles_interface.get(account_id, name)
		if results['roles'].empty?
			print red,bold, "\nRole not found by name '#{name}'\n\n",reset
			return nil
		end
		return results['roles'][0]
	end

	def add_account_option_types
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
			{'fieldName' => 'firstName', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
			{'fieldName' => 'role', 'fieldLabel' => 'Base Role', 'type' => 'text', 'displayOrder' => 3},
			{'fieldName' => 'currency', 'fieldLabel' => 'Currency', 'type' => 'text', 'displayOrder' => 4},
			{'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 5},
			{'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 6},
			{'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 7},
		]
	end

	def update_account_option_types
		add_account_option_types
	end

end
