# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Roles
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
		if args.empty?
			puts "\nUsage: morpheus roles [list]\n\n"
			exit 1
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus hosts [list] \n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			# todo: change this to Account Name and implement find_account_by_name
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |account_name|
				options[:account_name] = account_name
			end
			
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			account_id = nil # current user account by default
			if !options[:account_name].nil?
				found_account = find_account_by_name(options[:account_name])
				exit 1 if found_account.nil?
				account_id = found_account['id']
			end
			
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			
			json_response = @roles_interface.get(account_id, params)
			roles = json_response['roles']
			
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Roles\n","==================", reset, "\n\n"
				if roles.empty?
					puts yellow,"No roles found.",reset
				else
					# tp roles, [
					# 	'id',
					# 	'name',
					# 	'description',
					# 	'scope',
					# 	{'dateCreated' => {:display_name => "Date Created", :display_method => lambda{|it| format_local_dt(it['dateCreated']) } } }
					# ]
					roles_table = roles.collect do |role|
						{
							id: role['id'], 
							name: role['authority'], 
							description: role['description'], 
							scope: role['scope'], 
							dateCreated: format_local_dt(role['dateCreated']) 
						}
					end
					print cyan
					tp roles_table, [
						:id, 
						:name, 
						:description, 
						:scope, 
						{:dateCreated => {:display_name => "Date Created"} }
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
		print red,bold, "\nNOT YET IMPLEMENTED!\n\n",reset
		exit 1
	end

	def remove(args)
		print red,bold, "\nNOT YET IMPLEMENTED!\n\n",reset
		exit 1
	end

	private

	def find_account_by_name(name)
		results = @accounts_interface.get(name)
		if results['accounts'].empty?
			puts "Account not found by name #{name}"
			return nil
		end
		return results['accounts'][0]
	end

	def find_role_by_name(name)
		results = @roles_interface.get(name)
		if results['roles'].empty?
			puts "Role not found by name #{name}"
			return nil
		end
		return results['roles'][0]
	end

end
