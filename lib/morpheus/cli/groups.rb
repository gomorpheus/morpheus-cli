# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'


class Morpheus::Cli::Groups
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
	end

	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus groups [list,add,remove] [name]\n\n"
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\nUsage: morpheus groups [list,add,remove] [name]\n\n"
		end
	end

	def add(args)
		if args.count < 1
			puts "\nUsage: morpheus groups add [name] [--location]\n\n"
			return
		end
		params = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-l', '--location LOCATION', "Location" ) do |desc|
				params[:location] = desc
			end
		end
		optparse.parse(args)

		group = {name: args[0], location: params[:location]}
		begin
			@groups_interface.create(group)
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
		if args.count < 1
			puts "\nUsage: morpheus groups remove [name]\n\n"
			return
		end

		begin
			group_results = @groups_interface.get(args[0])
			if group_results['groups'].empty?
				puts "Group not found by name #{args[0]}"
				return
			end
			@groups_interface.destroy(group_results['groups'][0]['id'])
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
		begin
			json_response = @groups_interface.get()
			groups = json_response['groups']
			print "\n" ,cyan, bold, "Morpheus Groups\n","==================", reset, "\n\n"
			if groups.empty?
				puts yellow,"No groups currently configured.",reset
			else
				groups.each do |group|
					print cyan, "=  #{group['name']} - #{group['location']}\n"
				end
			end
			print reset,"\n\n"
			
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end
end