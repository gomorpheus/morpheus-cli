# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'
require 'morpheus/cli/option_types'

class Morpheus::Cli::Clouds
	include Morpheus::Cli::CliCommand
	include Morpheus::Cli::InfrastructureHelper

	register_subcommands :list, :get, :add, :remove, :firewall_disable, :firewall_enable, :security_groups, :apply_security_groups, :types => :list_cloud_types
	alias_subcommand :details, :get

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance

	end

	def connect(opts)
		if opts[:remote]
			@appliance_url = opts[:remote]
			@appliance_name = opts[:remote]
			@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials(opts)
		else
			@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials(opts)
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
		@clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			return 1
		end
		# preload stuff
		get_available_cloud_types()
	end

	def handle(args)
		handle_subcommand(args)
	end

	def list(args)
		options={}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			build_common_options(opts, options, [:list, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		connect(options)
		begin
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			if !options[:group].nil?
				group = find_group_by_name(options[:group])
				if !group.nil?
					params['groupId'] = group['id']
				end
			end

			if options[:dry_run]
				print_dry_run @clouds_interface.dry.get(params)
				return
			end

			json_response = @clouds_interface.get(params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				clouds = json_response['zones']
				print "\n" ,cyan, bold, "Morpheus Clouds\n","==================", reset, "\n\n"
				if clouds.empty?
					puts yellow,"No clouds found.",reset
				else
					print_clouds_table(clouds)
					print_results_pagination(json_response)
				end
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def get(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse.banner
			exit 1
		end
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			#json_response = {'zone' => cloud}
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.get(cloud['id'])
				return
			end
			json_response = @clouds_interface.get(cloud['id'])
			cloud = json_response['zone']
			server_counts = json_response['serverCounts']
			if options[:json]
				print JSON.pretty_generate(json_response)
				return
			end

			print "\n" ,cyan, bold, "Cloud Details\n","==================", reset, "\n\n"
			print cyan
			puts "ID: #{cloud['id']}"
			puts "Name: #{cloud['name']}"
			puts "Type: #{cloud_type_for_id(cloud['zoneTypeId'])}"
			puts "Location: #{cloud['location']}"
			puts "Visibility: #{cloud['visibility'].to_s.capitalize}"
			puts "Groups: #{cloud['groups'].collect {|it| it['name'] }.join(', ')}"
			status = nil
			if cloud['status'] == 'ok'
				status = "#{green}OK#{cyan}"
			elsif cloud['status'].nil?
				status = "#{white}UNKNOWN#{cyan}"
			else
				status = "#{red}#{cloud['status'] ? cloud['status'].upcase : 'N/A'}#{cloud['statusMessage'] ? "#{cyan} - #{cloud['statusMessage']}" : ''}#{cyan}"
			end
			puts "Status: #{status}"

			print "\n" ,cyan, "Cloud Servers (#{cloud['serverCount']})\n","==================", reset, "\n\n"
			print cyan
			if server_counts
			print "Container Hosts: #{server_counts['containerHost']}".center(20)
				print "Hypervisors: #{server_counts['hypervisor']}".center(20)
				print "Bare Metal: #{server_counts['baremetal']}".center(20)
				print "Virtual Machines: #{server_counts['vm']}".center(20)
				print "Unmanaged: #{server_counts['unmanaged']}".center(20)
				print "\n"
			end

			print reset,"\n"

			#puts instance
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] --group GROUP --type TYPE")
			opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
				params[:group] = val
			end
			opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
				params[:zone_type] = val
			end
			opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
				params[:description] = desc
			end
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		# if args.count < 1
		# 	puts optparse
		# 	exit 1
		# end
		connect(options)

		zone_payload = {name: args[0], description: params[:description]}

		begin

			# use active group by default
			params[:group] ||= @active_groups[@appliance_name.to_sym]

			# Group
	    group_id = nil
	    group = params[:group] ? find_group_by_name_or_id(params[:group]) : nil
	    if group
	      group_id = group["id"]
	    else
	      # print_red_alert "Group not found or specified!"
	      # exit 1
	      groups_dropdown = @groups_interface.get({})['groups'].collect {|it| {'name' => it["name"], 'value' => it["id"]} }
	      group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => groups_dropdown, 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
	      group_id = group_prompt['group']
	    end
	    zone_payload['groupId'] = group_id
	    # todo: pass groups as an array instead

	    # Cloud Name

			if args[0]
				zone_payload[:name] = args[0]
			elsif !options[:no_prompt]
				name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options])
				zone_payload[:name] = name_prompt['name']
			end

			# Cloud Type

	    cloud_type = nil
	    if params[:zone_type]
	      cloud_type = cloud_type_for_name(params[:zone_type])
	    elsif !options[:no_prompt]
	      # print_red_alert "Cloud Type not found or specified!"
	      # exit 1
	      cloud_types_dropdown = get_available_cloud_types().select {|it| it['enabled'] }.collect {|it| {'name' => it['name'], 'value' => it['code']} } 
	      cloud_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Type', 'selectOptions' => cloud_types_dropdown, 'required' => true, 'description' => 'Select Cloud Type.'}],options[:options],@api_client,{})
	      cloud_type_code = cloud_type_prompt['type']
	      cloud_type = cloud_type_for_name(cloud_type_code) # this does work
	    end
			if !cloud_type
				print_red_alert "A cloud type is required."
				exit 1
			end
			zone_payload[:zoneType] = {code: cloud_type['code']}
			
			# Cloud Type specific Option Types
			# TODO: I think we're missing some here..
			zone_payload.merge!(Morpheus::Cli::OptionTypes.prompt(cloud_type['optionTypes'],options[:options],@api_client))

			payload = {zone: zone_payload}
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.create(payload)
				return
			end
			json_response = @clouds_interface.create(payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		query_params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			opts.on( '-f', '--force', "Force Remove" ) do
				query_params[:force] = 'on'
			end
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			return
		end
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cloud #{cloud['name']}?")
				exit
			end
			json_response = @clouds_interface.destroy(cloud['id'], query_params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_disable(args)
		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			return
		end
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.firewall_disable(cloud['id'])
				return
			end
			json_response = @clouds_interface.firewall_disable(cloud['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_enable(args)
		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			return
		end
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.firewall_enable(cloud['id'])
				return
			end
			json_response = @clouds_interface.firewall_enable(cloud['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def security_groups(args)
		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			return
		end
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			zone_id = cloud['id']
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.security_groups(zone_id)
				return
			end
			json_response = @clouds_interface.security_groups(zone_id)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			securityGroups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups for Cloud: #{cloud['name']}\n","==================", reset, "\n\n"
			print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
			if securityGroups.empty?
				puts yellow,"No security groups currently applied.",reset
			else
				securityGroups.each do |securityGroup|
					print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
				end
			end
			print reset,"\n"

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def apply_security_groups(args)
		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [-s] [--clear]")
			opts.on( '-c', '--clear', "Clear all security groups" ) do
				options[:securityGroupIds] = []
				clear_or_secgroups_specified = true
			end
			opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
				options[:securityGroupIds] = secgroups.split(",")
				clear_or_secgroups_specified = true
			end
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if !clear_or_secgroups_specified 
			puts optparse
			exit
		end
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.apply_security_groups(cloud['id'])
				return
			end
			json_response = @clouds_interface.apply_security_groups(cloud['id'], options)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def list_cloud_types(args)
		options={}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			build_common_options(opts, options, [:json])
		end
		optparse.parse!(args)
		connect(options)
		begin
			if options[:dry_run]
				print_dry_run @clouds_interface.dry.cloud_types({})
				return
			end
			cloud_types = get_available_cloud_types() # @clouds_interface.dry.cloud_types({})['zoneTypes']
			if options[:json]
				print JSON.pretty_generate({zoneTypes: cloud_types})
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Cloud Types\n","==================", reset, "\n\n"
				if cloud_types.empty?
					puts yellow,"No cloud types found.",reset
				else
					print cyan
					cloud_types = cloud_types.select {|it| it['enabled'] }
					rows = cloud_types.collect do |cloud_type|
						{id: cloud_type['id'], name: cloud_type['name'], code: cloud_type['code']}
					end
					tp rows, :id, :name, :code
				end
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private

	def print_clouds_table(clouds, opts={})
    table_color = opts[:color] || cyan
    
    rows = clouds.collect do |cloud|
    	status = nil
			if cloud['status'] == 'ok'
				status = "#{green}OK#{table_color}"
			elsif cloud['status'].nil?
				status = "#{white}UNKNOWN#{table_color}"
			else
				status = "#{red}#{cloud['status'] ? cloud['status'].upcase : 'N/A'}#{cloud['statusMessage'] ? "#{table_color} - #{cloud['statusMessage']}" : ''}#{table_color}"
			end
			{
				id: cloud['id'], 
				name: cloud['name'], 
				type: cloud_type_for_id(cloud['zoneTypeId']), 
				location: cloud['location'], 
				groups: (cloud['groups'] || []).collect {|it| it['name'] }.join(', '),
				servers: cloud['serverCount'],
				status: status
			}
    end
    columns = [
    	:id, :name, :type, :location, :groups, :servers, :status
    ]
    print table_color
    tp rows, columns
    print reset

  end

end
