# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Instances
  include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus instances [list,add,remove,stop,start,restart,resize,upgrade,clone,envs,setenv,delenv,firewall_disable,firewall_enable,security_groups,apply_security_groups] [name]\n\n"
			return 
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
			when 'stop-service'
				stop_service(args[1..-1])
			when 'start-service'
				start_service(args[1..-1])
			when 'restart-service'
				restart_service(args[1..-1])
			when 'stats'
				stats(args[1..-1])
			when 'details'
				details(args[1..-1])
			when 'envs'
				envs(args[1..-1])
			when 'setenv'
				setenv(args[1..-1])	
			when 'delenv'
				delenv(args[1..-1])	
			when 'firewall_disable'
				firewall_disable(args[1..-1])	
			when 'firewall_enable'
				firewall_enable(args[1..-1])	
			when 'security_groups'	
				security_groups(args[1..-1])	
			when 'apply_security_groups'	
				apply_security_groups(args[1..-1])	
			when 'backup'
				backup(args[1..-1])	
			else
				puts "\nUsage: morpheus instances [list,add,remove,stop,start,restart,stop-service,start-service,restart-service,resize,upgrade,clone,envs,setenv,delenv] [name]\n\n"
				exit 127
		end
	end

	def add(args)
		if args.count < 2
			puts "\nUsage: morpheus instances add NAME TYPE\n\n"
			return
		end

		instance_name = args[0]
		instance_type_code = args[1]
		instance_type = find_instance_type_by_code(instance_type_code)
		if instance_type.nil?
			print reset,"\n\n"
			return
		end

		groupId = @active_groups[@appliance_name.to_sym]

		options = {
			:servicePlan => nil,
			:instance => {
				:name => instance_name,
				:site => {
					:id => groupId
				},
				:instanceType => {
					:code => instance_type_code
				}
			}
		}

		instance_type['instanceTypeLayouts'].sort! { |x,y| y['sortOrder'] <=> x['sortOrder'] }
		puts "Configurations: "
		instance_type['instanceTypeLayouts'].each_with_index do |layout, index|
			puts "  #{index+1}) #{layout['name']} (#{layout['code']})"
		end
		print "Selection: "
		layout_selection = nil
		layout = nil
		while true do
			layout_selection = $stdin.gets.chomp!
			if layout_selection.to_i.to_s == layout_selection
				layout_selection = layout_selection.to_i
				break
			end
		end
		layout = instance_type['instanceTypeLayouts'][layout_selection-1]['id']
		options[:instance][:layout] = {id: layout}
		print "\n"
		if options[:servicePlan].nil?
			plans = @instance_types_interface.service_plans(layout)
			puts "Select a Plan: "
			plans['servicePlans'].each_with_index do |plan, index|
				puts "  #{index+1}) #{plan['name']}"
			end
			print "Selection: "
			plan_selection = nil
			while true do
				plan_selection = $stdin.gets.chomp!
				if plan_selection.to_i.to_s == plan_selection
					plan_selection = plan_selection.to_i
					break
				end
			end
			options[:servicePlan] = plans['servicePlans'][plan_selection-1]['id']
			print "\n"
		end

		if !instance_type['config'].nil?
			instance_type_config = JSON.parse(instance_type['config'])
			if instance_type_config['options'].nil? == false
				instance_type_config['options'].each do |opt|
					print "#{opt['label']}: "
					if(opt['name'].downcase.include?("password"))
						options[opt['name']] = STDIN.noecho(&:gets).chomp!
						print "\n"
					else
						options[opt['name']] = $stdin.gets.chomp!
					end
					
				end
			end
		end
		begin
			@instances_interface.create(options)
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

	def envs(args)
		if args.count < 1
			puts "\nUsage: morpheus instances envs [name]\n\n"
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
			env_results = @instances_interface.get_envs(instance_id)
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", "\n\n", reset, cyan
			envs = env_results['envs'] || {}
			if env_results['readOnlyEnvs']
				envs += env_results['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") ? "********" : v, :export => true}}
			end
			tp envs, :name, :value, :export
			print "\n" ,cyan, bold, "Imported Envs\n","==================", "\n\n", reset, cyan
			 imported_envs = env_results['importedEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") ? "********" : v}}
			 tp imported_envs
			print reset, "\n"
			
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

	def setenv(args)
		if args.count < 3
			puts "\nUsage: morpheus instances setenv INSTANCE NAME VALUE [-e]\n\n"
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
			evar = {name: args[1], value: args[2], export: false}
			params = {}
			optparse = OptionParser.new do|opts|
				opts.on( '-e', "Exportable" ) do |exportable|
					evar[:export] = exportable
				end
			end
			optparse.parse(args)

			@instances_interface.create_env(instance_id, [evar])
			envs([args[0]])
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

	def delenv(args)
		if args.count < 2
			puts "\nUsage: morpheus instances setenv INSTANCE NAME\n\n"
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
			name = args[1]

			@instances_interface.del_env(instance_id, name)
			envs([args[0]])
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
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances stop [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.stop(instance_results['instances'][0]['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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

	def start(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances start [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.start(instance_results['instances'][0]['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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

	def restart(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances restart [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.restart(instance_results['instances'][0]['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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

		def stop_service(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances stop-service [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.stop(instance_results['instances'][0]['id'],false)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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

	def start_service(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances start-service [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.start(instance_results['instances'][0]['id'],false)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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

	def restart_service(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances restart-service [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.restart(instance_results['instances'][0]['id'],false)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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

	def backup(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances backup [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			json_response = @instances_interface.backup(instance_results['instances'][0]['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
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
				print cyan
				instance_table = instances.collect do |instance|
					{id: instance['id'], name: instance['name'], environment: instance['environment'], status: instance['status'], type: instance['instanceType']['name']}
				end
				tp instance_table, :id, :name, :type, :status
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

	def firewall_disable(args)
		if args.count < 1
			puts "\nUsage: morpheus instances firewall_disable [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@instances_interface.firewall_disable(instance_results['instances'][0]['id'])
			security_groups([args[0]])
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

	def firewall_enable(args)
		if args.count < 1
			puts "\nUsage: morpheus instances firewall_enable [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@instances_interface.firewall_enable(instance_results['instances'][0]['id'])
			security_groups([args[0]])
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

	def security_groups(args)
		if args.count < 1
			puts "\nUsage: morpheus instances security_groups [name]\n\n"
			return
		end
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end

			instance_id = instance_results['instances'][0]['id']
			json_response = @instances_interface.security_groups(instance_id)

			securityGroups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups for Instance:#{instance_id}\n","==================", reset, "\n\n"
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
			if e.response.code == 400
				error = JSON.parse(e.response.to_s)
				::Morpheus::Cli::ErrorHandler.new.print_errors(error)
			else
				puts "Error Communicating with the Appliance. Please try again later. #{e}"
			end
			return nil
		end
	end

	def apply_security_groups(args)
		usage = <<-EOF
Usage: morpheus instances apply_security_groups [name] [options]
EOF
		if args.count < 1
			puts usage
			return
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
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end

			@instances_interface.apply_security_groups(instance_results['instances'][0]['id'], options)
			security_groups([args[0]])
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

	def find_instance_type_by_code(code)
		instance_type_results = @instance_types_interface.get({code: code})
		if instance_type_results['instanceTypes'].empty?
			puts "Instance Type not found by code #{code}"
			return nil
		end
		return instance_type_results['instanceTypes'][0]
	end
end
