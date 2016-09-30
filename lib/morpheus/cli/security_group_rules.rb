# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityGroupRules
  include Morpheus::Cli::CliCommand

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@security_group_rules_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).security_group_rules
		@active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
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
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-s', '--secgroup SECGROUP', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			build_common_options(opts, options, [])
		end
		optparse.parse(args)

		if args.count < 3
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end

		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		params = {
			:rule => {
				:source => args[0],
				:portRange => args[1],
				:protocol => args[2],
				:customRule => true
			}
		}

		begin
			@security_group_rules_interface.create(security_group_id, params)
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add_instance_rule(args)
		usage = <<-EOT
Usage: morpheus security-group-rules add_instance_rule SOURCE_CIDR INSTANCE_TYPE_ID [options]
  SOURCE_CIDR: CIDR to white-list
  INSTANCE_TYPE_ID: ID of the Instance Type to access
EOT
		
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.count < 2
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		params = {
			:rule => {
				:source => args[0],
				:instanceTypeId => args[1]
			}
		}

		begin
			@security_group_rules_interface.create(security_group_id, params)
			list([security_group_id])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def list(args)
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = "\nUsage: morpheus security-group-rules list [ID]"
			build_common_options(opts, options, [:json])
		end
		security_group_id = args[0].to_i
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
			json_response = @security_group_rules_interface.get(security_group_id, params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
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
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus security-group-rules remove ID [options]"
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			build_common_options(opts, options, [])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		if security_group_id.nil?
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end

		begin
			@security_group_rules_interface.delete(security_group_id, args[0])
			list([security_group_id])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

end
