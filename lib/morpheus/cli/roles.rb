# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Roles
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
		if args.empty?
			puts "\nUsage: morpheus roles [list]\n\n"
			exit 1
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'details'
				details(args[1..-1])
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
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |account_name|
				options[:account_name] = account_name
			end
			
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			account_id = nil 
			if !options[:account_name].nil?
				account = @accounts_interface.find_account_by_name(options[:account_name])
				exit 1 if account.nil?
				account_id = account['id']
			end
			
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
					print_roles_table(roles)
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def details(args)
		usage = "Usage: morpheus roles details [name] [options]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-a', '--account ACCOUNT', "Account Name" ) do |account_name|
				options[:account_name] = account_name
			end

			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			account_id = nil 
			if !options[:account_name].nil?
				account = @accounts_interface.find_account_by_name(options[:account_name])
				exit 1 if account.nil?
				account_id = account['id']
			end
	
			# todo: roles_response = @roles_interface.list(account_id, {name: name}) instead
			#       there may be response data outside of role that needs to be displayed
			role = find_role_by_name(account_id, name)
			exit 1 if role.nil?

			if options[:json]
				print JSON.pretty_generate(role)
				print "\n"
			else
				print "\n" ,cyan, bold, "Role Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{role['id']}"
				puts "Name: #{role['authority']}"
				puts "Description: #{role['description']}"
				puts "Scope: #{role['scope']}"
				puts "Owner: #{role['owner'] ? role['owner']['name'] : nil}"
				puts "Date Created: #{format_local_dt(role['dateCreated'])}"
				puts "Last Updated: #{format_local_dt(role['lastUpdated'])}"
				print "\n" ,cyan, bold, "Role Instance Limits\n","==================", reset, "\n\n"
				print cyan
				puts "Max Storage (bytes): #{role['instanceLimits'] ? role['instanceLimits']['maxStorage'] : 0}"
				puts "Max Memory (bytes): #{role['instanceLimits'] ? role['instanceLimits']['maxMemory'] : 0}"
				puts "CPU Count: #{role['instanceLimits'] ? role['instanceLimits']['maxCpu'] : 0}"
				print cyan
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
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
	

end
