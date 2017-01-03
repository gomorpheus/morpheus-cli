require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::Instances
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

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
		@task_sets_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).task_sets
		@logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
		@tasks_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).tasks
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@provision_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).provision_types
		@options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end


	def handle(args) 
		usage = "Usage: morpheus instances [list,add,remove,stop,start,restart,backup,run-workflow,stop-service,start-service,restart-service,resize,upgrade,clone,envs,setenv,delenv] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
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
			when 'resize'
				resize(args[1..-1])
			when 'run-workflow'
				run_workflow(args[1..-1])
			when 'stats'
				stats(args[1..-1])
			when 'logs'
				logs(args[1..-1])
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
				puts "\n#{usage}\n\n"
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
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
			
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

		version_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'version', 'type' => 'select', 'fieldLabel' => 'Version', 'optionSource' => 'instanceVersions', 'required' => true, 'skipSingleOption' => true, 'description' => 'Select which version of the instance type to be provisioned.'}],options[:options],@api_client,{groupId: groupId, cloudId: cloud, instanceTypeId: instance_type['id']})
		layout_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'select', 'fieldLabel' => 'Layout', 'optionSource' => 'layoutsForCloud', 'required' => true, 'description' => 'Select which configuration of the instance type to be provisioned.'}],options[:options],@api_client,{groupId: groupId, cloudId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		layout_id = layout_prompt['layout']
		plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'optionSource' => 'instanceServicePlans', 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options],@api_client,{groupId: groupId, zoneId: cloud, instanceTypeId: instance_type['id'], layoutId: layout_id, version: version_prompt['version']})
		payload[:servicePlan] = plan_prompt['servicePlan']

		layout = instance_type['instanceTypeLayouts'].find{ |lt| lt['id'].to_i == layout_id.to_i}
		instance_type['instanceTypeLayouts'].sort! { |x,y| y['sortOrder'] <=> x['sortOrder'] }
		
		payload[:instance][:layout] = {id: layout['id']}

		
		begin
			service_plan_options_json = @instance_types_interface.service_plan_options(plan_prompt['servicePlan'], {cloudId: cloud, zoneId: cloud, layoutId: layout_id})
			
			# puts ""
			# print JSON.pretty_generate(service_plan_options_json)
			
			plan_options = service_plan_options_json['plan']
			volumes = prompt_instance_volumes(plan_options, options, @api_client, {})

			# puts "VOLUMES:"
			# print JSON.pretty_generate(volumes)

			if !volumes.empty?
				payload[:volumes] = volumes
			end

			# puts "\nexiting early...\n"
			# exit 1

		rescue RestClient::Exception => e
			print_red_alert "Unable to load options for selected plan."
			print_rest_exception(e, options)
			exit 1
		end

		type_payload = {}
		if !layout['optionTypes'].nil? && !layout['optionTypes'].empty?
			type_payload = Morpheus::Cli::OptionTypes.prompt(layout['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		elsif !instance_type['optionTypes'].nil? && !instance_type['optionTypes'].empty?
			type_payload = Morpheus::Cli::OptionTypes.prompt(instance_type['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		end
		if !type_payload['config'].nil?
			payload.merge!(type_payload['config'])
		end

		provision_payload = {}
		if !layout['provisionType'].nil? && !layout['provisionType']['optionTypes'].nil? && !layout['provisionType']['optionTypes'].empty?
			#puts "Checking for option Types"
			provision_payload = Morpheus::Cli::OptionTypes.prompt(layout['provisionType']['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
		end

		if !provision_payload.nil? && !provision_payload['config'].nil?
			payload.merge!(provision_payload['config'])
		end
		if !provision_payload.nil? && !provision_payload['server'].nil?
			payload[:server] = provision_payload['server']
		end

		# avoid 500 error
		payload[:servicePlanOptions] = {}

		begin
			if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "POST #{@appliance_url}/api/instances", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end
			json_response = @instances_interface.create(payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Provisioning instance #{instance_name}"
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def stats(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances stats [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			return
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
			stats = instance_results['stats'][instance_id.to_s]
			if options[:json]
				print JSON.pretty_generate(stats)
				print "\n"
			else
				print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", "\n\n", reset, cyan
				stats_map = {}
				stats_map[:memory] = "#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}"
				stats_map[:storage] = "#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}"
				stats_map[:cpu] = "#{stats['usedCpu'].to_f.round(2)}%"
				tp [stats_map], :memory,:storage,:cpu
				print reset, "\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def logs(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances logs [name]"
			opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
				options[:node_id] = node_id.to_i
			end
			build_common_options(opts, options, [:list, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			return
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			container_ids = instance['containers']
			if options[:node_id] && container_ids.include?(options[:node_id])
				container_ids = [options[:node_id]]
			end
			logs = @logs_interface.container_logs(container_ids, { max: options[:max] || 100, offset: options[:offset] || 0, query: options[:phrase]})
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
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances details [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			return
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
			stats = instance_results['stats'][instance_id.to_s]
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", reset, "\n\n"
			print cyan, "Memory: \t#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}\n"
			print cyan, "Storage: \t#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}\n\n",reset
			puts instance
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def envs(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances envs [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			env_results = @instances_interface.get_envs(instance['id'])
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", "\n\n", reset, cyan
			envs = env_results['envs'] || {}
			if env_results['readOnlyEnvs']
				envs += env_results['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value'], :export => true}}
			end
			tp envs, :name, :value, :export
			print "\n" ,cyan, bold, "Imported Envs\n","==================", "\n\n", reset, cyan
			 imported_envs = env_results['importedEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value']}}
			 tp imported_envs
			print reset, "\n"
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
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
			opts.on( '-M', "Masked" ) do |masked|
				options[:masked] = masked
			end
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 3
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			evar = {name: args[1], value: args[2], export: options[:export], masked: options[:masked]}
			params = {}
			@instances_interface.create_env(instance['id'], [evar])
			envs([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def delenv(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances setenv INSTANCE NAME"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 2
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			@instances_interface.del_env(instance['id'], args[1])
			envs([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def stop(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances stop [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop this instance?", options)
				exit 1
			end
			json_response = @instances_interface.stop(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def start(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances start [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			json_response = @instances_interface.start(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def restart(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances restart [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart this instance?", options)
				exit 1
			end
			json_response = @instances_interface.restart(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

		def stop_service(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances stop-service [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop this instance?", options)
				exit 1
			end
			json_response = @instances_interface.stop(instance['id'],false)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Stopping service on #{args[0]}"
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def start_service(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances start-service [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			json_response = @instances_interface.start(instance['id'],false)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Starting service on #{args[0]}"
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def restart_service(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances restart-service [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart this instance?", options)
				exit 1
			end
			json_response = @instances_interface.restart(instance['id'],false)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Restarting service on instance #{args[0]}"
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def resize(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances resize [name]"
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])

			group_id = instance['group']['id']
			cloud_id = instance['cloud']['id']
			layout_id = instance['layout']['id']

			plan_id = instance['plan']['id']
			payload = {}

			# avoid 500 error
			payload[:servicePlanOptions] = {}

			puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"


			#plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'optionSource' => 'instanceServicePlans', 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options],@api_client,{groupId: groupId, zoneId: cloud, instanceTypeId: instance_type['id'], layoutId: layout_id, version: version_prompt['version']})
			available_plans_result = @options_interface.options_for_source('instanceServicePlans',{groupId: group_id, zoneId: cloud_id, instanceTypeId: instance['instanceType']['id'], layoutId: layout_id, version: instance['instanceVersion']})
			available_plans = available_plans_result['data']
			available_plans.each do |plan|
				if plan['value'] && plan['value'].to_i == plan_id.to_i
					plan['name'] = "#{plan['name']} (current)"
				end
			end

			plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'New Plan', 'selectOptions' => available_plans, 'required' => true, 'description' => 'Choose the new plan for this instance'}],options[:options] )
			new_plan_id = plan_prompt['servicePlan']
			payload[:servicePlanId] = new_plan_id

			volumes_response = @instances_interface.volumes(instance['id'])
			current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

			begin
				service_plan_options_json = @instance_types_interface.service_plan_options(new_plan_id, {cloudId: cloud_id, zoneId: cloud_id, layoutId: layout_id})
				
				# puts ""
				# print JSON.pretty_generate(service_plan_options_json)
				
				plan_options = service_plan_options_json['plan']
				volumes = prompt_resize_instance_volumes(current_volumes, plan_options, options, @api_client, {})

				# puts "VOLUMES:"
				# print JSON.pretty_generate(volumes)

				if !volumes.empty?
					payload[:volumes] = volumes
				end

				# puts "\nexiting early...\n"
				# exit 1

			rescue RestClient::Exception => e
				print_red_alert "Unable to load options for selected plan."
				print_rest_exception(e, options)
				exit 1
			end

			# only amazon supports this option
			# for now, always do this
			payload[:deleteOriginalVolumes] = true

			json_response = @instances_interface.resize(instance['id'], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Resizing instance #{instance['name']}"
				list([])
			end
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def backup(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances backup [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1 
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			json_response = @instances_interface.backup(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Backup initiated."
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
				options[:group] = group
			end
			build_common_options(opts, options, [:list, :json, :remote])
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
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @instances_interface.get(params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				instances = json_response['instances']

				print "\n" ,cyan, bold, "Morpheus Instances\n","==================", reset, "\n\n"
				if instances.empty?
					puts yellow,"No instances currently configured.",reset
				else
					print cyan
					instance_table = instances.collect do |instance|
						status_string = instance['status']
						if status_string == 'running'
							status_string = "#{green}#{status_string.upcase}#{cyan}"
						elsif status_string == 'stopped' or status_string == 'failed'
							status_string = "#{red}#{status_string.upcase}#{cyan}"
						elsif status_string == 'unknown'
							status_string = "#{white}#{status_string.upcase}#{cyan}"
						else
							status_string = "#{yellow}#{status_string.upcase}#{cyan}"
						end
						connection_string = ''
						if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
							connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
						end
						{id: instance['id'], name: instance['name'], connection: connection_string, environment: instance['instanceContext'], nodes: instance['containers'].count, status: status_string, type: instance['instanceType']['name'], group: !instance['group'].nil? ? instance['group']['name'] : nil, cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil}
					end
					tp instance_table, :id, :name, :group, :cloud, :type, :environment, :nodes, :connection, :status
				end
				print reset,"\n\n"
			end
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		query_params = {keepBackups: 'off', force: 'off'}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances remove [name] [-fB]"
			opts.on( '-f', '--force', "Force Remove" ) do
				query_params[:force] = 'on'
			end
			opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
				query_params[:keepBackups] = 'on'
			end
			build_common_options(opts, options, [:auto_confirm, :json, :remote])

		end
		if args.count < 1
			puts "\n#{optparse}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove this instance?", options)
				exit 1
			end
			@instances_interface.destroy(instance['id'],query_params)
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_disable(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances firewall-disable [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			@instances_interface.firewall_disable(instance['id'])
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_enable(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances firewall-enable [name]"
			build_common_options(opts, options, [:json, :remote])
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
			print_rest_exception(e, options)
			exit 1
		end
	end

	def security_groups(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances security-groups [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name(args[0])
			instance_id = instance['id']
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
			print_rest_exception(e, options)
			exit 1
		end
	end

	def apply_security_groups(args)
		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances apply-security-groups [name] [options]"
			opts.on( '-c', '--clear', "Clear all security groups" ) do
				options[:securityGroupIds] = []
				clear_or_secgroups_specified = true
			end
			opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
				options[:securityGroupIds] = secgroups.split(",")
				clear_or_secgroups_specified = true
			end
			build_common_options(opts, options, [:json, :remote])
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
			instance = find_instance_by_name(args[0])
			@instances_interface.apply_security_groups(instance['id'], options)
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end


	def run_workflow(args)
		options = {}
		
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instances run-workflow [INSTANCE] [name] [options]"
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 2
			puts "\n#{optparse}\n\n"
			exit 1
		end
		
		optparse.parse(args)
		connect(options)
		instance = find_instance_by_name(args[0])
		workflow = find_workflow_by_name(args[1])
		task_types = @tasks_interface.task_types()
		editable_options = []
		workflow['taskSetTasks'].sort{|a,b| a['taskOrder'] <=> b['taskOrder']}.each do |task_set_task|
			task_type_id = task_set_task['task']['taskType']['id']
			task_type = task_types['taskTypes'].find{ |current_task_type| current_task_type['id'] == task_type_id}
			task_opts = task_type['optionTypes'].select { |otype| otype['editable']}
			if !task_opts.nil? && !task_opts.empty?
				editable_options += task_opts.collect do |task_opt|
					new_task_opt = task_opt.clone
					new_task_opt['fieldContext'] = "#{task_set_task['id']}.#{new_task_opt['fieldContext']}"
				end
			end
		end
		params = options[:options] || {}

		if params.empty? && !editable_options.empty?
			puts "\n#{optparse.banner}\n\n"
			option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
			puts "\nAvailable Options:\n#{option_lines}\n\n"
			exit 1
		end

		workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
		begin
			
			json_response = @instances_interface.workflow(instance['id'],workflow['id'], workflow_payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Running workflow..."
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private 
	
	def find_instance_by_name(name)
		instance_results = @instances_interface.get({name: name})
		if instance_results['instances'].empty?
			print_red_alert "Instance not found by name #{name}"
			exit 1
		end
		return instance_results['instances'][0]
	end
	def find_workflow_by_name(name)
		task_set_results = @task_sets_interface.get(name)
		if !task_set_results['taskSets'].nil? && !task_set_results['taskSets'].empty?
			return task_set_results['taskSets'][0]
		else
			print_red_alert "Workflow not found by name #{name}"
			exit 1
		end
	end
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
