# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityGroupRules
  include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@security_group_rules_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).security_group_rules
		@active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus security-group-rules [list, add_custom_rule, remove]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add_custom_rule'
				add_custom_rule(args[1..-1])
			when 'add_instance_rule'
				add_instance_rule(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus security-group-rules [list,add_custom_rule,remove]\n\n"
		end
	end

	def add_custom_rule(args)
		usage = <<-EOT
Usage: morpheus security-group-rules add_custom_rule SOURCE_CIDR PORT_RANGE PROTOCOL [options]
  SOURCE_CIDR: CIDR to white-list
  PORT_RANGE: Port value (i.e. 123) or port range (i.e. 1-65535)
  PROTOCOL: tcp, udp, icmp\n\n'
EOT

		if args.count < 3
			puts usage
			return
		end
		
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-group-rules add_custom_rule SOURCE_CIDR PORT_RANGE PROTOCOL [options]"
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
		end
		optparse.parse(args)

		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		options = {
			:rule => {
				:source => args[0],
				:portRange => args[1],
				:protocol => args[2],
				:customRule => true
			}
		}

		begin
			@security_group_rules_interface.create(security_group_id, options)
		rescue => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			return nil
		end
		list([])
	end

	def add_instance_rule(args)
		usage = <<-EOT
Usage: morpheus security-group-rules add_instance_rule SOURCE_CIDR INSTANCE_TYPE_ID [options]
  SOURCE_CIDR: CIDR to white-list
  INSTANCE_TYPE_ID: ID of the Instance Type to access
EOT
		if args.count < 2
			puts usage
			return
		end
		
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = "\nmorpheus security-group-rules add_instance_rule SOURCE_CIDR INSTANCE_TYPE_ID [options]"
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
		end
		optparse.parse(args)

		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		options = {
			:rule => {
				:source => args[0],
				:instanceTypeId => args[1]
			}
		}

		begin
			@security_group_rules_interface.create(security_group_id, options)
		rescue => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			return nil
		end
		list([])
	end

	def list(args)
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-group-rules list [options]"
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
		end
		optparse.parse(args)

		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		begin
			params = {}
			json_response = @security_group_rules_interface.get(security_group_id, options)
			rules = json_response['rules']
			print "\n" ,cyan, bold, "Morpheus Security Group Rules for Security Group ID:#{security_group_id}\n","==================", reset, "\n\n"
			if rules.empty?
				puts yellow,"No Security Group Rules currently configured.",reset
			else
				rules.each do |rule|
					print cyan, "=  #{rule['id']} - (CIDR:#{rule['source']}, Port Range:#{rule['portRange']}, Protocol:#{rule['protocol']}, Custom Rule:#{rule['customRule']}, Instance Type:#{rule['instanceTypeId']})\n"
				end
			end
			print reset,"\n\n"
			
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

	def remove(args)
		if args.count < 1
			puts "\nUsage: morpheus security-group-rules remove ID [options]\n\n"
			return
		end

		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-group-rules remove ID [options]"
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
		end
		optparse.parse(args)

		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		begin
			@security_group_rules_interface.delete(security_group_id, args[0])
			list([])
		rescue RestClient::Exception => e
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			return nil
		end
	end

end
