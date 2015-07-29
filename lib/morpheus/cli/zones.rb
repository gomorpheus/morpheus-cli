# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'


class Morpheus::Cli::Zones
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@zones_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).zones
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@zone_types = @zones_interface.zone_types['zoneTypes']
	end

	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus zones [list,add,remove] [name]\n\n"
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
				puts "\nUsage: morpheus zones [list,add,remove] [name]\n\n"
		end
	end

	def add(args)
		if args.count < 1
			puts "\nUsage: morpheus zones add [name] --group GROUP --type TYPE\n\n"
			return
		end
		params = {zone_type: 'standard'}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				params[:group] = group
			end
			opts.on( '-t', '--type TYPE', "Zone Type" ) do |zone_type|
				params[:zone_type] = zone_type
			end
			opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
				params[:description] = desc
			end
		end
		optparse.parse(args)
		zone = {name: args[0], description: params[:description]}
		if !params[:group].nil?
			group = find_group_by_name(params[:group])
			if !group.nil?
				zone['groupId'] = group['id']
			end
		end

		if !params[:zone_type].nil?
			zone['zoneType'] = {code:zone_type_code_for_name(params[:zone_type])}
		end
		
		begin
			@zones_interface.create(zone)
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
			puts "\nUsage: morpheus zones remove [name] --group GROUP\n\n"
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
			puts "\nUsage: morpheus zones remove [name] --group GROUP"
			return
		end


		begin
			zone_results = @zones_interface.get({name: args[0], groupId: params[:groupId]})
			if zone_results['zones'].empty?
				puts "Zone not found by name #{args[0]}"
				return
			end
			@zones_interface.destroy(zone_results['zones'][0]['id'])
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
					params['groupId'] = group['id']
				end
			end

			json_response = @zones_interface.get(params)
			zones = json_response['zones']
			print "\n" ,cyan, bold, "Morpheus Zones\n","==================", reset, "\n\n"
			if zones.empty?
				puts yellow,"No zones currently configured.",reset
			else
				zones.each do |zone|
					print cyan, "=  #{zone['name']} (#{zone_type_for_id(zone['zoneTypeId'])}) - #{zone['description']}\n"
				end
			end
			print reset,"\n\n"
			
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

	private

	def zone_type_for_id(id)
		if !@zone_types.empty?
			zone_type = @zone_types.find { |z| z['id'].to_i == id.to_i}
			if !zone_type.nil?
				return zone_type['name']
			end
		end
		return nil
	end

	def zone_type_code_for_name(name)
		if !@zone_types.empty?
			zone_type = @zone_types.find { |z| z['name'].downcase == name.downcase}
			if !zone_type.nil?
				return zone_type['code']
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