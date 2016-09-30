require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Groups
  include Morpheus::Cli::CliCommand
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file

	end

	def handle(args) 
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus groups [list,add,remove] [name]\n\n"
			return
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'use'
				use(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus groups [list,add,remove] [name]\n\n"
		end
	end

	def add(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus groups add [name] [--location]"
			opts.on( '-l', '--location LOCATION', "Location" ) do |desc|
				params[:location] = desc
			end
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		group = {name: args[0], location: params[:location]}
		begin
			@groups_interface.create(group)
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus groups remove [name]"
			build_common_options(opts, options, [:auto_confirm])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end

		begin
			group_results = @groups_interface.get(args[0])
			if group_results['groups'].empty?
				print_red_alert "Group not found by name #{args[0]}"
				exit 1
			end
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the group #{group_results['groups'][0]['name']}?")
				exit
			end
			@groups_interface.destroy(group_results['groups'][0]['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus groups list"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		begin
			json_response = @groups_interface.get()
			if options[:json]
				print JSON.pretty_generate(json_response)
				return
			end
			groups = json_response['groups']
			print "\n" ,cyan, bold, "Morpheus Groups\n","==================", reset, "\n\n"
			if groups.empty?
				puts yellow,"No groups currently configured.",reset
			else
				groups.each do |group|
					if @active_groups[@appliance_name.to_sym] == group['id']
						print cyan, bold, "=> #{group['name']} - #{group['location']}",reset,"\n"
					else
						print cyan, "=  #{group['name']} - #{group['location']}\n",reset
					end
				end
			end
			print reset,"\n\n"
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def use(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus groups use [name]"
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.length < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		begin
			json_response = @groups_interface.get(args[0])
			groups = json_response['groups']
			if groups.length > 0
				@active_groups[@appliance_name.to_sym] = groups[0]['id']
				::Morpheus::Cli::Groups.save_groups(@active_groups)
				list([])
			else
				print_red_alert "Group not found by name #{args[0]}"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	# Provides the current active group information
	def self.active_group
		appliance_name, appliance_url = Morpheus::Cli::Remote.active_appliance
		if !defined?(@@groups)
			@@groups = load_group_file
		end
		return @@groups[appliance_name.to_sym]
	end

	

	def self.load_group_file
		remote_file = groups_file_path
		if File.exist? remote_file
			return YAML.load_file(remote_file)
		else
			{}
		end
	end

	def self.groups_file_path
		home_dir = Dir.home
		morpheus_dir = File.join(home_dir,".morpheus")
		if !Dir.exist?(morpheus_dir)
			Dir.mkdir(morpheus_dir)
		end
		return File.join(morpheus_dir,"groups")
	end

	def self.save_groups(group_map)
		File.open(groups_file_path, 'w') {|f| f.write group_map.to_yaml } #Store
	end
end
