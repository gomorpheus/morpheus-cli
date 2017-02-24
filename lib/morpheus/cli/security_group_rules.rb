# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityGroupRules
  include Morpheus::Cli::CliCommand

	register_subcommands :list, :'add-custom-rule', :'add-instance-rule', :remove

	def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
		@security_group_rules_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).security_group_rules
		@active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
	end

	def handle(args)
		handle_subcommand(args)
	end

	def add_custom_rule(args)
		usage = <<-EOT
Usage: morpheus #{command_name} add-custom-rule SOURCE_CIDR PORT_RANGE PROTOCOL [options]
  SOURCE_CIDR: CIDR to white-list
  PORT_RANGE: Port value (i.e. 123) or port range (i.e. 1-65535)
  PROTOCOL: tcp, udp, icmp
EOT
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-s', '--secgroup SECGROUP', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)

		if args.count < 3
			puts optparse.banner
			exit 1
		end

		if security_group_id.nil? && @active_security_group
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit 1
		end

		params = {
			:rule => {
				:source => args[0],
				:portRange => args[1],
				:protocol => args[2],
				:customRule => true
			}
		}
		connect(options)
		begin
			if options[:dry_run]
				print_dry_run @security_group_rules_interface.dry.create(security_group_id, params)
				return
			end
			json_response = @security_group_rules_interface.create(security_group_id, params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			list([security_group_id])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add_instance_rule(args)
		usage = <<-EOT
Usage: morpheus #{command_name} add_instance_rule SOURCE_CIDR INSTANCE_TYPE_ID [options]
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
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 2
			puts optparse.banner
			exit 1
		end
		if security_group_id.nil? && @active_security_group
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
		connect(options)
		begin
			if options[:dry_run]
				print_dry_run @security_group_rules_interface.dry.create(security_group_id, params)
				return
			end
			json_response = @security_group_rules_interface.create(security_group_id, params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
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
			opts.banner = subcommand_usage("[id]")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		security_group_id = args[0]
		if security_group_id.nil? && @active_security_group
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit 1
		end
		connect(options)
		begin
			params = {}
			if options[:dry_run]
				print_dry_run @security_group_rules_interface.dry.get(security_group_id, params)
				return
			end
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
				rules = rules.sort {|x,y| x["id"] <=> y["id"] }
				rules.each do |rule|
					print cyan, "=  #{rule['id']} - (CIDR:#{rule['source']}, Port Range:#{rule['portRange']}, Protocol:#{rule['protocol']}, Custom Rule:#{rule['customRule']}, Instance Type:#{rule['instanceTypeId']})\n"
				end
			end
			print reset,"\n"
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		security_group_id = nil 
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[id] [options]")
			opts.on( '-s', '--secgroup secgroup', "Security Group ID (Use will use security as set with 'security-groups use id'" ) do |id|
				security_group_id = id
			end
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		if security_group_id.nil? && @active_security_group
			security_group_id = @active_security_group[@appliance_name.to_sym]
		end

		if security_group_id.nil?
			puts "Security Group ID must be specified with options or set using 'security-groups use id'"
			exit
		end
		connect(options)
		begin
			if options[:dry_run]
				print_dry_run @security_group_rules_interface.dry.delete(security_group_id, args[0])
				return
			end
			json_response = @security_group_rules_interface.delete(security_group_id, args[0])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			list([security_group_id])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

end
