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
		@instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@provision_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).provision_types
		@options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
	end


	def handle(args) 
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
			when 'firewall-disable'
				firewall_disable(args[1..-1])	
			when 'firewall-enable'
				firewall_enable(args[1..-1])	
			when 'security-groups'	
				security_groups(args[1..-1])	
			when 'apply-security-groups'	
				apply_security_groups(args[1..-1])	
			when 'backup'
				backup(args[1..-1])	
			else
				puts "\nUsage: morpheus instances [list,add,remove,stop,start,restart,stop-service,start-service,restart-service,resize,upgrade,clone,envs,setenv,delenv] [name]\n\n"
				exit 127
		end
	end

	def add(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances add TYPE NAME"
			opts.on( '-g', '--group GROUP', "Group" ) do |val|
				options[:group] = val
			end
			opts.on( '-c', '--cloud CLOUD', "Cloud" ) do |val|
				options[:cloud] = val
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
			
		end

		if args.count < 2
			puts "\n#{optparse}\n\n"
			return
		end
		optparse.parse(args)
		connect(options)
		instance_name = args[1]
		instance_type_code = args[0]
		instance_type = find_instance_type_by_code(instance_type_code)
		if instance_type.nil?
			exit 1
		end
		groupId = nil
		if !options[:group].nil?
			group = find_group_by_name(options[:group])
			if !group.nil?
				groupId = group
			end
		else
			groupId = @active_groups[@appliance_name.to_sym]	
		end

		if groupId.nil?
			puts "Group not found or specified! \n #{optparse}"
			exit 1
		end

		if options[:cloud].nil?
			puts "Cloud not specified! \n #{optparse}"
			exit 1
		end
		cloud = find_cloud_by_name(groupId,options[:cloud])
		if cloud.nil?
			puts "Cloud not found! \n #{optparse}"
			exit 1
		end

		payload = {
			:servicePlan => nil,
			zoneId: cloud,
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

		version_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'version', 'type' => 'select', 'fieldLabel' => 'Version', 'optionSource' => 'instanceVersions', 'required' => true, 'description' => 'Select which version of the instance type to be provisioned.'}],options[:options],@api_client,{groupId: groupId, cloudId: cloud, instanceTypeId: instance_type['id']})
		layout_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'select', 'fieldLabel' => 'Layout', 'optionSource' => 'layoutsForCloud', 'required' => true, 'description' => 'Select which configuration of the instance type to be provisioned.'}],options[:options],@api_client,{groupId: groupId, cloudId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		layout_id = layout_prompt['layout']
		plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'optionSource' => 'instanceServicePlans', 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options],@api_client,{groupId: groupId, zoneId: cloud, instanceTypeId: instance_type['id'], layoutId: layout_id, version: version_prompt['version']})
		payload[:servicePlan] = plan_prompt['servicePlan']
		layout = instance_type['instanceTypeLayouts'].find{ |lt| lt['id'].to_i == layout_id.to_i}
		instance_type['instanceTypeLayouts'].sort! { |x,y| y['sortOrder'] <=> x['sortOrder'] }
		
		payload[:instance][:layout] = {id: layout['id']}

		type_payload = {}
		if !layout['optionTypes'].nil? && layout['optionTypes'].empty?
			type_payload = Morpheus::Cli::OptionTypes.prompt(layout['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		elsif !instance_type['optionTypes'].nil? && instance_type['optionTypes'].empty?
			type_payload = Morpheus::Cli::OptionTypes.prompt(instance_type['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		end
		if !type_payload['config'].nil?
			payload.merge!(type_payload['config'])
		end

		provision_payload = {}
		if !layout['provisionType'].nil? && !layout['provisionType']['optionTypes'].nil? && !layout['provisionType']['optionTypes'].empty?
			puts "Checking for option Types"
			provision_payload = Morpheus::Cli::OptionTypes.prompt(layout['provisionType']['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		end

		if !provision_payload.nil? && !provision_payload['config'].nil?
			payload.merge!(provision_payload['config'])
		end

		begin
			@instances_interface.create(payload)
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
			puts "\nUsage: morpheus instances details [name]\n\n"
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
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances envs [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
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
			exit 1
		end
	end

	def setenv(args)
		options = {}

		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances setenv INSTANCE NAME VALUE [-e]"
			opts.on( '-e', "Exportable" ) do |exportable|
					options[:export] = exportable
				end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 3
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			instance = instance_results['instances'][0]
			instance_id = instance['id']
			evar = {name: args[1], value: args[2], export: options[:export]}
			params = {}
			@instances_interface.create_env(instance_id, [evar])
			envs([args[0]])
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

	def delenv(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances setenv INSTANCE NAME"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 2
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
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
		connect(options)
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
		connect(options)
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
		connect(options)
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
		connect(options)
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
		connect(options)
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
		connect(options)
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
		connect(options)
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
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			params = {}
			if !options[:group].nil?
				group = find_group_by_name(options[:group])
				if !group.nil?
					params['site'] = group
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
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances remove [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance_results = @instances_interface.get({name: args[0]})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
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
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances firewall-disable [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
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
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances firewall-enable [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
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
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances security-groups [name]"
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
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
		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances apply-security-groups [name] [options]"
			opts.banner = usage
			opts.on( '-c', '--clear', "Clear all security groups" ) do
				options[:securityGroupIds] = []
				clear_or_secgroups_specified = true
			end
			opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
				options[:securityGroupIds] = secgroups.split(",")
				clear_or_secgroups_specified = true
			end
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)

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

		option_results = @options_interface.options_for_source('groups',{})
		match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
		if match.nil?
			return nil
		else
			return match['value']
		end
	end

	def find_cloud_by_name(groupId,name)

		option_results = @options_interface.options_for_source('clouds',{groupId: groupId})
		match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
		if match.nil?
			return nil
		else
			return match['value']
		end
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
