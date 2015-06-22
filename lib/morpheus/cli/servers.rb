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
		params = {server_type: 'standard'}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				params[:group] = group
			end
			opts.on( '-t', '--type TYPE', "Server Type" ) do |server_type|
				params[:server_type] = server_type
			end
			opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
				params[:description] = desc
			end
		end
		optparse.parse(args)
		server = {name: args[0], description: params[:description]}
		if !params[:group].nil?
			group = find_group_by_name(params[:group])
			if !group.nil?
				server['groupId'] = group['id']
			end
		end

		if !params[:server_type].nil?
			server['serverType'] = {code:server_type_code_for_name(params[:server_type])}
		end
		
		begin
			@servers_interface.create(server)
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