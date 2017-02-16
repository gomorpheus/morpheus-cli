# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Clouds
	include Morpheus::Cli::CliCommand

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
		@cloud_types = @clouds_interface.cloud_types['zoneTypes']
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			return 1
		end
	end

	def handle(args) 

		if args.empty?
			puts "\nUsage: morpheus clouds [list,details,add,remove,firewall_disable,firewall_enable,security_groups,apply_security_groups] [name]\n\n"
			return
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
			when 'firewall_disable'
				firewall_disable(args[1..-1])	
			when 'firewall_enable'
				firewall_enable(args[1..-1])	
			when 'security_groups'	
				security_groups(args[1..-1])	
			when 'apply_security_groups'	
				apply_security_groups(args[1..-1])		
			else
				puts "\nUsage: morpheus clouds [list,add,remove,firewall_disable,firewall_enable,security_groups,apply_security_groups] [name]\n\n"
				exit 127 #Command now foud exit code
		end
	end

	def list(args)
		options={}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus clouds list"
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			build_common_options(opts, options, [:list, :json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			params = {}
			if !options[:group].nil?
				group = find_group_by_name(options[:group])
				if !group.nil?
					params['groupId'] = group['id']
				end
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
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus clouds details [name]"
			build_common_options(opts, options, [:json])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			cloud = find_cloud_by_name_or_id(args[0])
			#json_response = {'zone' => cloud}
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
			puts "Location: #{cloud['location']}"
			puts "Groups: #{cloud['groups'].collect {|it| it['name'] }.join(', ')}"
			puts "Total Servers: #{cloud['serverCount']}"
			if server_counts
				# if server_counts['host'] && server_counts['host'] != 0
				# 	puts "Host: #{server_counts['host']}"
				# end
				if server_counts['containerHost'] && server_counts['containerHost'] != 0
					puts "Container: #{server_counts['containerHost']}"
				end
				if server_counts['hypervisor'] && server_counts['hypervisor'] != 0
					puts "Hypervisor: #{server_counts['hypervisor']}"
				end
				if server_counts['baremetal'] && server_counts['baremetal'] != 0
					puts "Bare Metal: #{server_counts['baremetal']}"
				end
				if server_counts['vm'] && server_counts['vm'] != 0
					puts "VM: #{server_counts['vm']}"
				end
				if server_counts['unmanaged'] && server_counts['unmanaged'] != 0
					puts "Unmanaged: #{server_counts['unmanaged']}"
				end
			end

			print "\n\n",reset

			#puts instance
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		options = {}
		params = {zone_type: 'standard'}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus clouds add [name] --group GROUP --type TYPE"
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				params[:group] = group
			end
			opts.on( '-t', '--type TYPE', "Cloud Type" ) do |zone_type|
				params[:zone_type] = zone_type
			end
			opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
				params[:description] = desc
			end
			build_common_options(opts, options, [:options, :json, :remote])
		end
		optparse.parse!(args)

		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end

		connect(options)
		zone = {name: args[0], description: params[:description]}
		if !params[:group].nil?
			group = find_group_by_name(params[:group])
			if !group.nil?
				zone['groupId'] = group['id']
			end
		end

		if !params[:zone_type].nil?
			cloud_type = cloud_type_for_name(params[:zone_type])
			zone['zoneType'] = {code: cloud_type['code']}
		end
		
		begin
			zone.merge!(Morpheus::Cli::OptionTypes.prompt(cloud_type['optionTypes'],options[:options],@api_client))
			json_response = @clouds_interface.create(zone)
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
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus clouds remove [name] --group GROUP"
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		optparse.parse(args)

		if args.count < 2
			puts "\n#{optparse.banner}\n\n"
			return
		end

		connect(options)
		if !options[:group].nil?
			group = find_group_by_name(options[:group])
			if !group.nil?
				options[:groupId] = group['id']
			else
				puts "\nGroup #{options[:group]} not found!"
				exit 1
			end
		end


		begin
			zone_results = @clouds_interface.get({name: args[0]})
			if zone_results['zones'].empty?
				puts "Zone not found by name #{args[0]}"
				exit 1
			end
			cloud = zone_results['zones'][0]
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cloud #{cloud['name']}?")
				exit
			end
			json_response = @clouds_interface.destroy(cloud['id'])
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
		if args.count < 1
			puts "\nUsage: morpheus clouds firewall_disable [name]\n\n"
			return
		end
		begin
			zone_results = @clouds_interface.get({name: args[0]})
			if zone_results['zones'].empty?
				puts "Zone not found by name #{args[0]}"
				exit 1
			end
			@clouds_interface.firewall_disable(zone_results['zones'][0]['id'])
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_enable(args)
		if args.count < 1
			puts "\nUsage: morpheus clouds firewall_enable [name]\n\n"
			return
		end
		begin
			zone_results = @clouds_interface.get({name: args[0]})
			if zone_results['zones'].empty?
				puts "Zone not found by name #{args[0]}"
				exit 1
			end
			@clouds_interface.firewall_enable(zone_results['zones'][0]['id'])
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def security_groups(args)
		if args.count < 1
			puts "\nUsage: morpheus clouds security_groups [name]\n\n"
			return
		end
		begin
			zone_results = @clouds_interface.get({name: args[0]})
			if zone_results['zones'].empty?
				puts "Zone not found by name #{args[0]}"
				exit 1
			end

			zone_id = zone_results['zones'][0]['id']
			json_response = @clouds_interface.security_groups(zone_id)

			securityGroups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups for Zone:#{zone_id}\n","==================", reset, "\n\n"
			print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
			if securityGroups.empty?
				puts yellow,"No security groups currently applied.",reset
			else
				securityGroups.each do |securityGroup|
					print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
				end
			end
			print reset,"\n\n"

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def apply_security_groups(args)
		usage = <<-EOF
Usage: morpheus clouds apply_security_groups [name] [options]
EOF
		if args.count < 1
			puts usage
			exit 1
		end

		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-c', '--clear', "Clear all security groups" ) do
				options[:securityGroupIds] = []
				clear_or_secgroups_specified = true
			end
			opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
				options[:securityGroupIds] = secgroups.split(",")
				clear_or_secgroups_specified = true
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
		end
		optparse.parse(args)

		if !clear_or_secgroups_specified 
			puts usage
			exit
		end

		begin
			zone_results = @clouds_interface.get({name: args[0]})
			if zone_results['zones'].empty?
				puts "Zone not found by name #{args[0]}"
				exit 1
			end

			@clouds_interface.apply_security_groups(zone_results['zones'][0]['id'], options)
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private
	
	def find_cloud_by_id(id)
		json_results = @clouds_interface.get(id.to_i)
		if json_results['zone'].empty?
			print_red_alert "Cloud not found by id #{id}"
			exit 1
		end
		cloud = json_results['cloud']
		return cloud
	end

	def find_cloud_by_name(name)
		json_results = @clouds_interface.get({name: name})
		if json_results['zones'].empty?
			print_red_alert "Cloud not found by name #{name}"
			exit 1
		end
		cloud = json_results['zones'][0]
		return cloud
	end

	def find_cloud_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_cloud_by_id(val)
		else
			return find_cloud_by_name(val)
		end
	end

	def cloud_type_for_id(id)
		if !@cloud_types.empty?
			zone_type = @cloud_types.find { |z| z['id'].to_i == id.to_i}
			if !zone_type.nil?
				return zone_type['name']
			end
		end
		return nil
	end

	def cloud_type_for_name(name)
		if !@cloud_types.empty?
			zone_type = @cloud_types.find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
			if !zone_type.nil?
				return zone_type
			end
		end
		return nil
	end

	def find_group_by_name(name)
		group_results = @groups_interface.get(name)
		if group_results['groups'].empty?
			puts "Group not found by name #{name}"
			return nil
		end
		return group_results['groups'][0]
	end

	def find_group_by_id(id)
		group_results = @groups_interface.get(id)
		if group_results['groups'].empty?
			puts "Group not found by id #{id}"
			return nil
		end
		return group_results['groups'][0]
	end

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
