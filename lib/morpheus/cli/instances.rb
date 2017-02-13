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
		usage = "Usage: morpheus instances [list,details,add,update,remove,stop,start,restart,backup,run-workflow,stop-service,start-service,restart-service,resize,upgrade,clone,envs,setenv,delenv] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'details'
				details(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				update(args[1..-1])
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
			opts.banner = "Usage: morpheus instances add [type] [name]"
			opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
				options[:group_name] = val
			end
			opts.on( '-G', '--group-id ID', "Group Id" ) do |val|
				options[:group_id] = val
			end
			opts.on( '-c', '--cloud CLOUD', "Cloud Name" ) do |val|
				options[:cloud_name] = val
			end
			# this conflicts with --nocolor option
			# opts.on( '-C', '--cloud CLOUD', "Cloud Id" ) do |val|
			# 	options[:cloud] = val
			# end
			opts.on( '-t', '--type CODE', "Instance Type" ) do |val|
				options[:instance_type_code] = val
			end
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
			
		end

		optparse.parse(args)
		connect(options)

		# support old format of `instance add TYPE NAME`
		if args[0] && args[0] !~ /\A\-/
			options[:instance_type_code] = args[0]
			if args[1] && args[1] !~ /\A\-/
				options[:instance_name] = args[1]
			end
		end
		
		# use active group by default
		if !options[:group_name] && !options[:group_id]
			options[:group_id] = @active_groups[@appliance_name.to_sym]
		end

		options[:name_required] = true
		
		begin

			payload = prompt_new_instance(options)

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
				instance_name = json_response["instance"]["name"]
				print_green_success "Provisioning instance #{instance_name}"
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args)
		usage = "Usage: morpheus instances update [name] [options]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse(args)
    if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
    connect(options)

    begin
  		
  		instance = find_instance_by_name_or_id(args[0])

			# group = find_group_from_options(options)

			payload = {
				'instance' => {id: instance["id"]}
			}

			update_instance_option_types = [
				{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this instance'},
				{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
				{'fieldName' => 'instanceContext', 'fieldLabel' => 'Environment', 'type' => 'select', 'required' => false, 'selectOptions' => instance_context_options()},
				{'fieldName' => 'tags', 'fieldLabel' => 'Tags', 'type' => 'text', 'required' => false}
			]

			params = options[:options] || {}

      if params.empty?
        puts "\n#{usage}\n"
        option_lines = update_instance_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      instance_keys = ['name', 'description', 'instanceContext', 'tags']
      params = params.select {|k,v| instance_keys.include?(k) }
      params['tags'] = params['tags'].split(',').collect {|it| it.to_s.strip }.compact.uniq if params['tags']
      payload['instance'].merge!(params)
			
      json_response = @instances_interface.update(instance["id"], payload)

      if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "PUT #{@appliance_url}/api/instances", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated instance #{instance['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
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
			instance = find_instance_by_name_or_id(args[0])
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
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			# JD: woah..fix the api withStats logic.. until then re-fetch via index?name=
			instance = find_instance_by_name_or_id(args[0])
			instance_results = @instances_interface.get({name: instance['name']})
			if instance_results['instances'].empty?
				puts "Instance not found by name #{args[0]}"
				exit 1
			end
			instance = instance_results['instances'][0]
			instance_id = instance['id']
			stats = instance_results['stats'][instance_id.to_s]
			if options[:json]
				print JSON.pretty_generate({instance: instance, stats: stats})
				return
			end
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", reset, "\n\n"
			print cyan, "Memory: \t#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}\n"
			print cyan, "Storage: \t#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}\n\n",reset
			# TODO: print useful info
			#puts instance
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])

			group_id = instance['group']['id']
			cloud_id = instance['cloud']['id']
			layout_id = instance['layout']['id']

			plan_id = instance['plan']['id']
			payload = {}

			# avoid 500 error
			# payload[:servicePlanOptions] = {}

			puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"

			# prompt for service plan
			service_plans_json = @instances_interface.service_plans({zoneId: cloud_id, layoutId: layout_id})
			service_plans = service_plans_json["plans"]
			service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
			service_plans_dropdown.each do |plan|
				if plan['value'] && plan['value'].to_i == plan_id.to_i
					plan['name'] = "#{plan['name']} (current)"
				end
			end
			plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options])
			service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['servicePlan'].to_i }
			new_plan_id = service_plan["id"]
			#payload[:servicePlan] = new_plan_id # ew, this api uses servicePlanId instead
			payload[:servicePlanId] = new_plan_id

			volumes_response = @instances_interface.volumes(instance['id'])
			current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

			# prompt for volumes
			volumes = prompt_resize_volumes(current_volumes, service_plan, options, @api_client, {})
			if !volumes.empty?
				payload[:volumes] = volumes
			end

			# only amazon supports this option
			# for now, always do this
			payload[:deleteOriginalVolumes] = true

			if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "POST #{@appliance_url}/api/instances/#{instance['id']}", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end
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
			instance = find_instance_by_name_or_id(args[0])
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
			opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
				options[:group_name] = val
			end
			build_common_options(opts, options, [:list, :json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			params = {}
			group = find_group_from_options(options)
			if group
				params['site'] = group['id']
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
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the instance '#{instance['name']}'?", options)
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
			instance = find_instance_by_name_or_id(args[0])
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
		instance = find_instance_by_name_or_id(args[0])
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
	
	def find_instance_by_id(id)
		instance_results = @instances_interface.get(id.to_i)
		if instance_results['instance'].empty?
			print_red_alert "Instance not found by id #{id}"
			exit 1
		end
		return instance_results['instance']
	end

	def find_instance_by_name(name)
		instance_results = @instances_interface.get({name: name})
		if instance_results['instances'].empty?
			print_red_alert "Instance not found by name #{name}"
			exit 1
		end
		return instance_results['instances'][0]
	end

	def find_instance_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_instance_by_id(val)
		else
			return find_instance_by_name(val)
		end
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

end
