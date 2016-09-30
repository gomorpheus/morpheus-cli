# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityGroups
  include Morpheus::Cli::CliCommand

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@security_groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).security_groups
		@active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus security-groups [list,get,add,remove,use] [name]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'get'	
				get(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'use'
				use(args[1..-1])
			else
				puts "\nUsage: morpheus security-groups [list,get,add,remove,use] [name]\n\n"
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-groups list"
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		begin
			json_response = @security_groups_interface.list()
			security_groups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups\n","==================", reset, "\n\n"
			if security_groups.empty?
				puts yellow,"No Security Groups currently configured.",reset
			else
				security_groups.each do |security_group|
					
					if @active_security_group[@appliance_name.to_sym] = security_group['id']
						print cyan, "=> #{security_group['id']}: #{security_group['name']} (#{security_group['description']})\n"
					else
						print cyan, "=  #{security_group['id']}: #{security_group['name']} (#{security_group['description']})\n"
					end
				end
			end
			print reset,"\n\n"
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def get(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus security-groups get ID"
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end

		begin
			json_response = @security_groups_interface.get({id: args[0]})
			security_group = json_response['securityGroup']
			print "\n" ,cyan, bold, "Morpheus Security Group\n","==================", reset, "\n\n"
			if security_group.nil?
				puts yellow,"Security Group not found by id #{args[0]}",reset
			else
				print cyan, "=  #{security_group['id']}: #{security_group['name']} (#{security_group['description']})\n"
			end
			print reset,"\n\n"
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		options = {}
		params = {:securityGroup => {:name => args[0]} }
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-groups add NAME [options]"
			opts.on( '-d', '--description Description', "Description of the security group" ) do |description|
				params[:securityGroup][:description] = description
			end
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		begin
			@security_groups_interface.create(params)
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-groups remove ID"
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			return
		end
		begin
			json_response = @security_groups_interface.get({id: args[0]})
			security_group = json_response['securityGroup']
			if security_group.nil?
				puts "Security Group not found by id #{args[0]}"
				return
			end
			@security_groups_interface.delete(security_group['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def use(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus security-groups use ID"
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.length < 1
			puts "\n#{optparse.banner}\n\n"
			return
		end
		begin
			json_response = @security_groups_interface.get({id: args[0]})
			security_group = json_response['securityGroup']
			if !security_group.nil?
				@active_security_group[@appliance_name.to_sym] = security_group['id']
				::Morpheus::Cli::SecurityGroups.save_security_group(@active_security_group)
				puts "Using Security Group #{args[0]}"
			else
				puts "Security Group not found"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def self.load_security_group_file
		remote_file = security_group_file_path
		if File.exist? remote_file
			return YAML.load_file(remote_file)
		else
			{}
		end
	end

	def self.security_group_file_path
		home_dir = Dir.home
		morpheus_dir = File.join(home_dir,".morpheus")
		if !Dir.exist?(morpheus_dir)
			Dir.mkdir(morpheus_dir)
		end
		return File.join(morpheus_dir,"securitygroup")
	end

	def self.save_security_group(security_group_map)
		File.open(security_group_file_path, 'w') {|f| f.write security_group_map.to_yaml } #Store
	end

end
