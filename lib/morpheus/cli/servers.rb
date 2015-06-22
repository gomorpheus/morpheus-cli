# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'


class Morpheus::Cli::Servers
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@servers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).servers
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@zones_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).zones
		@zone_types = @zones_interface.zone_types['zoneTypes']
	end

	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus servers [list,add,remove] [name]\n\n"
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus servers [list,add,remove] [name]\n\n"
		end
	end

	def add(args)
		if args.count < 1
			puts "\nUsage: morpheus servers add [name] --group GROUP --type TYPE\n\n"
			return
		end
		options = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			opts.on( '-z', '--zone ZONE', "Zone Name" ) do |group|
				options[:zone] = group
			end
			opts.on( '-d', '--description DESCRIPTION', "Server Description" ) do |desc|
				options[:description] = desc
			end
		end
		zone=nil
		optparse.parse(args)
		if !params[:group].nil?
			group = find_group_by_name(params[:group])
			if !group.nil?
				options['groupId'] = group['id']
			end
			if !params[:zone].nil?
				zone = find_zone_by_name(options['groupId'], params[:zone])
				if !zone.nil?
					options['zoneId'] = zone['id']
				end
			end
		end

		if options['zoneId'].nil?
			puts red,bold,"\nEither the zone was not specified or was not found. Please make sure a zone is specified with --zone\n\n"
			return
		end

		zone_type = zone_type_for_id(zone['zoneTypeId'])
		begin
			case zone_type['code']
				when 'standard'
					add_standard(args[0],options[:description],zone, args)
					list([])
				when 'openstack'
					add_openstack(args[0],options[:description],zone, args)
					list([])
				when 'amazon'
					add_amazon(args[0],options[:description],zone, args)
					list([])
				else
					puts "Unsupported Zone Type: This version of the morpheus cli does not support the requested zone type"
			end		
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

	def remove(args)
		if args.count < 2
			puts "\nUsage: morpheus servers remove [name] --group GROUP\n\n"
			return
		end

		params = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				params[:group] = group
			end
		end
		optparse.parse(args)

		if !params[:group].nil?
			group = find_group_by_name(params[:group])
			if !group.nil?
				params[:groupId] = group['id']
			else
				puts "\nGroup #{params[:group]} not found!"
				return
			end
		else params[:group].nil?
			puts "\nUsage: morpheus servers remove [name] --group GROUP"
			return
		end


		begin
			server_results = @servers_interface.get({name: args[0], groupId: params[:groupId]})
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
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
		end
		optparse.parse(args)
		begin
			params = {}
			if !options[:group].nil?
				group = find_group_by_name(options[:group])
				if !group.nil?
					params['site'] = group['id']
				end
			end

			json_response = @servers_interface.get(params)
			servers = json_response['servers']
			print "\n" ,red, bold, "Morpheus Servers\n","==================", reset, "\n\n"
			if servers.empty?
				puts yellow,"No servers currently configured.",reset
			else
				servers.each do |server|
					print red, "=  #{server['name']} - #{server['description']} (#{server['status']})\n"
				end
			end
			print reset,"\n\n"
			
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

private


	def add_openstack(name, description,zone, args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-s', '--size SIZE', "Disk Size" ) do |size|
				options[:diskSize] = size.to_l
			end
			opts.on('-i', '--image IMAGE', "Image Name") do |image|
				options[:imageName] = image
			end

			opts.on('-f', '--flavor FLAVOR', "Flavor Name") do |flavor|
				options[:flavorName] = flavor
			end
		end
		optparse.parse(args)

		server_payload = {server: {name: name, description: description}, zoneId: zone['id']}
		response = @servers_interface.create(server_payload)
	end

	def add_standard(name,description,zone, args)
		options = {}
		networkOptions = {name: 'eth0'}
		optparse = OptionParser.new do|opts|
			opts.on( '-u', '--ssh-user USER', "SSH Username" ) do |sshUser|
				options['sshUser'] = sshUser
			end
			opts.on('-p', '--password PASSWORD', "SSH Password (optional)") do |password|
				options['sshPassowrd'] = password
			end

			opts.on('-h', '--host HOST', "HOST IP") do |host|
				options['sshHost'] = host
			end

			options['dataDevice'] = '/dev/sdb'
			opts.on('-m', '--data-device DATADEVICE', "Data device for LVM") do |device|
				options['dataDevice'] = device
			end

			
			opts.on('-n', '--interface NETWORK', "Default Network Interface") do |net|
				networkOptions[:name] = net
			end
		end
		optparse.parse(args)

		server_payload = {server: {name: name, description: description}.merge(options), network: networkOptions, zoneId: zone['id']}
		response = @servers_interface.create(server_payload)

	end

	def add_amazon(name,description,zone, args)
		puts "NOT YET IMPLEMENTED"
	end

	def zone_type_for_id(id)
		if !@zone_types.empty?
			zone_type = @zone_types.find { |z| z['id'].to_i == id.to_i}
			if !zone_type.nil?
				return zone_type['name']
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
end