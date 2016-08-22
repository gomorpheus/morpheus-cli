# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
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
		@clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@servers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).servers
		@cloud_types = @clouds_interface.cloud_types['zoneTypes']
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
	end

	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus hosts [list,add,remove] [name]\n\n"
			return
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus hosts [list,add,remove] [name]\n\n"
		end
	end

	def add(args)
		if args.count < 2
			puts "\nUsage: morpheus hosts add CLOUD [name]\n\n"
			return
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
		if !options[:group].nil?
			group = find_group_by_name(options[:group])
			if !group.nil?
				options['groupId'] = group['id']
			end
		else
			options['groupId'] = @active_groups[@appliance_name.to_sym]
		end

		if !options['groupId'].nil?
			if !options[:zone].nil?
				zone = find_zone_by_name(options['groupId'], options[:zone])
				if !zone.nil?
					options['zoneId'] = zone['id']
				end
			end
		end

		if options['zoneId'].nil?
			puts red,bold,"\nEither the zone was not specified or was not found. Please make sure a zone is specified with --zone\n\n", reset
			return
		end

		zone_type = zone_type_for_id(zone['zoneTypeId'])
		begin
			server_payload = {server: {name: name, description: description, zone: {id: zone['id']}}.merge(options)}
			response = @servers_interface.create(server_payload)
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

	def remove(args)
		if args.count < 1
			puts "\nUsage: morpheus hosts remove [name]\n\n"
			return
		end
		options = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			server_results = @servers_interface.get({name: args[0]})
			if server_results['servers'].empty?
				puts "Server not found by name #{args[0]}"
				return
			end
			@servers_interface.destroy(server_results['servers'][0]['id'])
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
					servers.each do |server|
						print red, "=  #{server['name']} - #{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'} (#{server['status']})\n"
					end
				end
				print reset,"\n\n"
			end
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

private

	def zone_type_for_id(id)
		# puts "Zone Types #{@zone_types}"
		if !@cloud_types.empty?
			zone_type = @cloud_types.find { |z| z['id'].to_i == id.to_i}
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

	def find_zone_by_name(groupId, name)
		zone_results = @clouds_interface.get({groupId: groupId, name: name})
		if zone_results['zones'].empty?
			puts "Zone not found by name #{name}"
			return nil
		end
		return zone_results['zones'][0]
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
