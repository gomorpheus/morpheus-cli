# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Hosts
	include Term::ANSIColor
    include Morpheus::Cli::CliCommand
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
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
		@servers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).servers
		@cloud_types = @clouds_interface.cloud_types['zoneTypes']
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
	end

	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus hosts [list,add,remove] [name]\n\n"
			exit 1
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'server-types'
				server_types(args[1..-1])
			else
				puts "\nUsage: morpheus hosts [list,add,remove] [name]\n\n"
				exit 127 #Command now foud exit code
		end
	end

	def server_types(args) 
		if args.count < 1
			puts "\nUsage: morpheus hosts server-types CLOUD\n\n"
			exit 1
		end
		options = {zone: args[0]}

		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus server add CLOUD NAME -t HOST_TYPE [options]"
			opts.on( '-t', '--type TYPE', "Host Type" ) do |server_type|
				options[:server_type] = server_type
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end

		optparse.parse(args)
		connect(options)
		params = {}
		
		zone=nil


		if !options[:zone].nil?
			zone = find_zone_by_name(nil, options[:zone])
		end

		if zone.nil?
			puts "Cloud not found"
			exit 1
		else
			zone_type = cloud_type_for_id(zone['zoneTypeId'])
		end
		server_types = zone_type['serverTypes'].select{|b| b['creatable'] == true}
		if options[:json]
			print JSON.pretty_generate(server_types)
			print "\n"
		else
			
			print "\n" ,red, bold, "Morpheus Server Types\n","==================", reset, "\n\n"
			if server_types.nil? || server_types.empty?
				puts yellow,"No server types found for the selected cloud.",reset
			else
				server_types.each do |server_type|
					print red, "=  #{server_type['code']} - #{server_type['name']}\n"
				end
			end
			print reset,"\n\n"
		end
	end

	def add(args)
		if args.count < 2
			puts "\nUsage: morpheus hosts add CLOUD [name]\n\n"
			return
		end
		options = {zone: args[0], params:{}}
		name = args[1]

		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus server add CLOUD NAME -t HOST_TYPE [options]"
			opts.on( '-t', '--type TYPE', "Host Type" ) do |server_type|
				options[:server_type] = server_type
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)

		params = {}
		
		zone=nil
		if !options[:zone].nil?
			zone = find_zone_by_name(nil, options[:zone])
			options[:params][:zoneId] = zone['id']
		end

		if zone.nil?
			puts  red,bold,"\nEither the cloud was not specified or was not found. Please make sure a cloud is specied at the beginning of the argument\n\n",reset
			return
		else
			zone_type = cloud_type_for_id(zone['zoneTypeId'])
		end
		server_type = zone_type['serverTypes'].find{|b| b['creatable'] == true && (b['code'] == options[:server_type] || b['name'] == options[:server_type])}
		params = Morpheus::Cli::OptionTypes.prompt(server_type['optionTypes'],options[:options],@api_client, options[:params])
		begin
			server_payload = {server: {name: name, zone: {id: zone['id']}, computeServerType: [id: server_type['id']]}.merge(params['server']), config: params['config'], network: params['network']}
			response = @servers_interface.create(server_payload)
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
		if args.count < 1
			puts "\nUsage: morpheus hosts remove [name] [-c CLOUD] [-f] [-S]\n\n"
			return
		end
		options = {}
		query_params = {name: args[0], removeResources: 'on', force: 'off'}
		optparse = OptionParser.new do|opts|
			opts.on( '-c', '--cloud CLOUD', "Cloud" ) do |cloud|
				options[:zone] = cloud
			end
			opts.on( '-f', '--force', "Force Remove" ) do
				query_params[:force] = 'on'
			end
			opts.on( '-S', '--skip-remove-infrastructure', "Skip removal of underlying cloud infrastructure" ) do
				query_params[:removeResources] = 'off'
			end
			
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		zone=nil
		if !options[:zone].nil?
			zone = find_zone_by_name(nil, options[:zone])
		end

		begin
			
			if zone 
				query_params[:zoneId] = zone['id']
			end
			server = nil
			server_results = @servers_interface.get(query_params)
			if server_results['servers'].nil? || server_results['servers'].empty?
				server_results = @servers_interface.get(args[0].to_i)
				server = server_results['server']
			else
				if !server_results['servers'].empty? && server_results['servers'].count > 1
					puts "Multiple Servers exist with the same name. Try scoping by cloud or using id to confirm"
					exit 1
				end
				server = server_results['servers'][0] unless server_results['servers'].empty?
			end

			if server.nil?
				puts "Server not found by name #{args[0]}"
				exit 1
			else
				
			end
			
			if !::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove this server?", options)
				exit 1
			end

			json_response = @servers_interface.destroy(server['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Removing Server..."
			end
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

	def list(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			
			if !options[:group].nil?
				group = find_group_by_name(options[:group])
				if !group.nil?
					params['site'] = group['id']
				end
			end
			if !options[:max].nil?
				params['max'] = options[:max]
			end
			if !options[:offset].nil?
				params['offset'] = options[:offset]
			end
			if !options[:phrase].nil?
				params['phrase'] = options[:phrase]
			end
			json_response = @servers_interface.get(params)
			servers = json_response['servers']
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,red, bold, "Morpheus Hosts\n","==================", reset, "\n\n"
				if servers.empty?
					puts yellow,"No hosts currently configured.",reset
				else
					

					server_table =servers.collect do |server|
						power_state = nil
						if server['powerState'] == 'on'
							power_state = "#{green}ON#{red}"
						elsif server['powerState'] == 'off'
							power_state = "#{red}OFF#{red}"
						else
							power_state = "#{white}#{server['powerState'].upcase}#{red}"
						end
						{id: server['id'], name: server['name'], platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A', type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged', status: server['status'], power: power_state}
						# print red, "= [#{server['id']}] #{server['name']} - #{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'} (#{server['status']}) Power: ", power_state, "\n"
					end
				end
				print red
				tp server_table, :id, :name, :type, :platform, :status, :power
				print reset,"\n\n"
			end
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

private
	def find_group_by_name(name)
		group_results = @groups_interface.get(name)
		if group_results['groups'].empty?
			puts "Group not found by name #{name}"
			return nil
		end
		return group_results['groups'][0]
	end

	def find_zone_by_name(groupId, name)
		zone_results = @clouds_interface.get({groupId: groupId, name: name})
		if zone_results['zones'].empty?
			puts "Zone not found by name #{name}"
			return nil
		end
		return zone_results['zones'][0]
	end

	def find_server_type(zone, name)
		server_type = zone['serverTypes'].select do  |sv_type|
			(sv_type['name'].downcase == name.downcase || sv_type['code'].downcase == name.downcase) && sv_type['creatable'] == true
		end
		if server_type.nil?
			puts "Server Type Not Selectable"
		end
		return server_type
	end

	def cloud_type_for_id(id)
		if !@cloud_types.empty?
			zone_type = @cloud_types.find { |z| z['id'].to_i == id.to_i}
			if !zone_type.nil?
				return zone_type
			end
		end
		return nil
	end

	def find_group_by_id(id)
		group_results = @groups_interface.get(id)
		if group_results['groups'].empty?
			puts "Group not found by id #{id}"
			return nil
		end
		return group_results['groups'][0]
	end
end
