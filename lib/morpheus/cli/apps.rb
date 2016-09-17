# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Apps
  include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@apps_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).apps
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@apps_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).apps
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
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
			else
				puts "\nUsage: morpheus apps [list,add,remove,stop,start,restart,resize,upgrade,clone,envs,setenv,delenv,firewall_disable,firewall_enable,security_groups,apply_security_groups] [name]\n\n"
		end
	end

	def add(args)
		if args.count < 2
			puts "\nUsage: morpheus apps add NAME TYPE\n\n"
			return
		end

		app_name = args[0]
		instance_type_code = args[1]
		instance_type = find_instance_type_by_code(instance_type_code)
		if instance_type.nil?
			print reset,"\n\n"
			return
		end

		groupId = @active_groups[@appliance_name.to_sym]

		options = {
			:servicePlan => nil,
			:app => {
				:name => app_name,
				:site => {
					:id => groupId
				},
				:appType => {
					:code => instance_type_code
				}
			}
		}

		instance_type['appTypeLayouts'].sort! { |x,y| y['sortOrder'] <=> x['sortOrder'] }
		puts "Configurations: "
		instance_type['appTypeLayouts'].each_with_index do |layout, index|
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
		layout = instance_type['appTypeLayouts'][layout_selection-1]['id']
		options[:app][:layout] = {id: layout}
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
			@apps_interface.create(options)
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

	def logs(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps logs [name] [options]"
			build_common_options(opts, options, [:list, :json])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			return
		end
		optparse.parse(args)
		connect(options)
		begin
			app = find_app_by_name(args[0])
			containers = []
			app['appTiers'].each do |app_tier|
				app_tier['appInstances'].each do |app_instance|
					containers += app_instance['instance']['containers']
				end
			end
			logs = @logs_interface.container_logs(containers, { max: options[:max] || 100, offset: options[:offset] || 0, query: options[:phrase]})
			if options[:json]
				puts logs
			else
				logs['data'].reverse.each do |log_entry|
					log_level = ''
					case log_entry['level']
						when 'INFO'
							log_level = "#{blue}#{bold}INFO#{reset}"
						when 'DEBUG'
							log_level = "#{white}#{bold}DEBUG#{reset}"
						when 'WARN'
							log_level = "#{yellow}#{bold}WARN#{reset}"
						when 'ERROR'
							log_level = "#{red}#{bold}ERROR#{reset}"
						when 'FATAL'
							log_level = "#{red}#{bold}FATAL#{reset}"
					end
					puts "[#{log_entry['ts']}] #{log_level} - #{log_entry['message']}"
				end
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def stats(args)
		if args.count < 1
			puts "\nUsage: morpheus apps stats [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			app = app_results['apps'][0]
			app_id = app['id']
			stats = app_results['stats'][app_id.to_s]
			print "\n" ,cyan, bold, "#{app['name']} (#{app['appType']['name']})\n","==================", reset, "\n\n"
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
			puts "\nUsage: morpheus apps stats [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			app = app_results['apps'][0]
			app_id = app['id']
			stats = app_results['stats'][app_id.to_s]
			print "\n" ,cyan, bold, "#{app['name']} (#{app['appType']['name']})\n","==================", reset, "\n\n"
			print cyan, "Memory: \t#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}\n"
			print cyan, "Storage: \t#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}\n\n",reset
			puts app
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
			puts "\nUsage: morpheus apps envs [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			app = app_results['apps'][0]
			app_id = app['id']
			env_results = @apps_interface.get_envs(app_id)
			print "\n" ,cyan, bold, "#{app['name']} (#{app['appType']['name']})\n","==================", "\n\n", reset, cyan
			envs = env_results['envs'] || {}
			if env_results['readOnlyEnvs']
				envs += env_results['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") ? "********" : v, :export => true}}
			end
			tp envs, :name, :value, :export
			print "\n" ,cyan, bold, "Importad Envs\n","==================", "\n\n", reset, cyan
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
			puts "\nUsage: morpheus apps setenv INSTANCE NAME VALUE [-e]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			app = app_results['apps'][0]
			app_id = app['id']
			evar = {name: args[1], value: args[2], export: false}
			params = {}
			optparse = OptionParser.new do|opts|
				opts.on( '-e', "Exportable" ) do |exportable|
					evar[:export] = exportable
				end
			end
			optparse.parse(args)

			@apps_interface.create_env(app_id, [evar])
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
			puts "\nUsage: morpheus apps setenv INSTANCE NAME\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			app = app_results['apps'][0]
			app_id = app['id']
			name = args[1]

			@apps_interface.del_env(app_id, name)
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
		if args.count < 1
			puts "\nUsage: morpheus apps stop [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@apps_interface.stop(app_results['apps'][0]['id'])
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
			puts "\nUsage: morpheus apps start [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@apps_interface.start(app_results['apps'][0]['id'])
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
			puts "\nUsage: morpheus apps restart [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@apps_interface.restart(app_results['apps'][0]['id'])
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

			json_response = @apps_interface.get(params)
			apps = json_response['apps']
			print "\n" ,cyan, bold, "Morpheus Apps\n","==================", reset, "\n\n"
			if apps.empty?
				puts yellow,"No apps currently configured.",reset
			else
				apps.each do |app|
					print cyan, "=  #{app['name']}\n"
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
			puts "\nUsage: morpheus apps remove [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end
			@apps_interface.destroy(app_results['apps'][0]['id'])
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
			puts "\nUsage: morpheus apps firewall_disable [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "App not found by name #{args[0]}"
				return
			end
			@apps_interface.firewall_disable(app_results['apps'][0]['id'])
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
			puts "\nUsage: morpheus apps firewall_enable [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "App not found by name #{args[0]}"
				return
			end
			@apps_interface.firewall_enable(app_results['apps'][0]['id'])
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
			puts "\nUsage: morpheus apps security_groups [name]\n\n"
			return
		end
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "Instance not found by name #{args[0]}"
				return
			end

			app_id = app_results['apps'][0]['id']
			json_response = @apps_interface.security_groups(app_id)

			securityGroups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups for App:#{app_id}\n","==================", reset, "\n\n"
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
Usage: morpheus apps apply_security_groups [name] [options]
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
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				puts "App not found by name #{args[0]}"
				return
			end

			@apps_interface.apply_security_groups(app_results['apps'][0]['id'], options)
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

	def find_app_by_name(name)
		app_results = @apps_interface.get({name: name})
		if app_results['apps'].empty?
			puts "Instance not found by name #{name}"
			exit 1
		end
		return app_results['apps'][0]
	end
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
		if instance_type_results['appTypes'].empty?
			puts "Instance Type not found by code #{code}"
			return nil
		end
		return instance_type_results['appTypes'][0]
	end
end
