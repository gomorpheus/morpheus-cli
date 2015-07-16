# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'filesize'

class Morpheus::Cli::Instances
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus instances [list,add,remove,stop,start,restart,resize,upgrade,clone] [name]\n\n"
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'stop'
				stop(args[1..-1])
			when 'start'
				start(args[1..-1])
			when 'restart'
				restart(args[1..-1])
			when 'stats'
				stats(args[1..-1])
			when 'details'
				details(args[1..-1])
			else
				puts "\nUsage: morpheus instances [list,add,remove,stop,start,restart,resize,upgrade,clone] [name]\n\n"
		end
	end

	def add(args)
	end

	def stats(args)
		if args.count < 1
			puts "\nUsage: morpheus instances stats [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			instance = instance_results['instances'][0]
			instance_id = instance['id']
			stats = instance_results['stats'][instance_id.to_s]
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", reset, "\n\n"
			print cyan, "Memory: \t#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}\n"
			print cyan, "Storage: \t#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}\n\n",reset
			puts 
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

	def details(args)
		if args.count < 1
			puts "\nUsage: morpheus instances stats [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			instance = instance_results['instances'][0]
			instance_id = instance['id']
			stats = instance_results['stats'][instance_id.to_s]
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", reset, "\n\n"
			print cyan, "Memory: \t#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}\n"
			print cyan, "Storage: \t#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}\n\n",reset
			puts instance
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

	def stop(args)
		if args.count < 1
			puts "\nUsage: morpheus instances stop [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@instances_interface.stop(instance_results['instances'][0]['id'])
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

	def start(args)
		if args.count < 1
			puts "\nUsage: morpheus instances start [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@instances_interface.start(instance_results['instances'][0]['id'])
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

	def restart(args)
		if args.count < 1
			puts "\nUsage: morpheus instances restart [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@instances_interface.restart(instance_results['instances'][0]['id'])
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

			json_response = @instances_interface.get(params)
			instances = json_response['instances']
			print "\n" ,cyan, bold, "Morpheus Instances\n","==================", reset, "\n\n"
			if instances.empty?
				puts yellow,"No instances currently configured.",reset
			else
				instances.each do |instance|
					print cyan, "=  #{instance['name']} (#{instance['instanceType']['name']}) - #{instance['status']['name']}\n"
				end
			end
			print reset,"\n\n"
			
		rescue => e
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
			return nil
		end
	end

	def remove(args)
		if args.count < 1
			puts "\nUsage: morpheus instances remove [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@instances_interface.destroy(instance_results['instances'][0]['id'])
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

private 
	def find_group_by_name(name)
		group_results = @groups_interface.get(name)
		if group_results['groups'].empty?
			puts "Group not found by name #{name}"
			return nil
		end
		return group_results['groups'][0]
	end
end