require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/option_types'

class Morpheus::Cli::Instances
	include Morpheus::Cli::CliCommand
	include Morpheus::Cli::ProvisioningHelper

	register_subcommands :list, :get, :add, :update, :remove, :stats, :stop, :start, :restart, :suspend, :eject, :backup, :backups, :stop_service, :start_service, :restart_service, :resize, :upgrade, :clone, :envs, :setenv, :delenv, :security_groups, :apply_security_groups, :firewall_enable, :firewall_disable, :run_workflow, :import_snapshot
	alias_subcommand :details, :get

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
		@clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
		@provision_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).provision_types
		@options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end
	
	def handle(args)
		handle_subcommand(args)
	end

	def add(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[type] [name]")
			opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
				options[:group] = val
			end
			opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
				options[:cloud] = val
			end
			opts.on( '-t', '--type CODE', "Instance Type" ) do |val|
				options[:instance_type_code] = val
			end
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
			
		end

		optparse.parse!(args)
		connect(options)

		# support old format of `instance add TYPE NAME`
		if args[0]
			options[:instance_type_code] = args[0]
		end
		if args[1]
			options[:instance_name] = args[1]
		end
		
		# use active group by default
		options[:group] ||= @active_groups[@appliance_name.to_sym]

		options[:name_required] = true
		
		begin

			payload = prompt_new_instance(options)

			if options[:dry_run]
				print_dry_run @instances_interface.dry.create(payload)
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:options, :json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)

		begin

			instance = find_instance_by_name_or_id(args[0])

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
			
			if options[:dry_run]
				print_dry_run @instances_interface.dry.update(instance["id"], payload)
				return
			end
			json_response = @instances_interface.update(instance["id"], payload)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Updated instance #{instance['name']}"
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.get(instance['id'])
				return
			end
			json_response = @instances_interface.get(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			instance = json_response['instance']
			stats = json_response['stats'] || {}
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", "\n\n", reset, cyan
			stats_map = {}
			stats_map[:memory] = "#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}"
			stats_map[:storage] = "#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}"
			stats_map[:cpu] = "#{stats['usedCpu'].to_f.round(2)}%"
			tp [stats_map], :memory,:storage,:cpu
			print reset, "\n"
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def logs(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
				options[:node_id] = node_id.to_i
			end
			build_common_options(opts, options, [:list, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			container_ids = instance['containers']
			if options[:node_id] && container_ids.include?(options[:node_id])
				container_ids = [options[:node_id]]
			end
			query_params = { max: options[:max] || 100, offset: options[:offset] || 0, query: options[:phrase]}
			if options[:dry_run]
				print_dry_run @logs_interface.dry.container_logs(container_ids, query_params)
				return
			end
			logs = @logs_interface.container_logs(container_ids, query_params)
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

	def get(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			if options[:dry_run]
				if args[0].to_s =~ /\A\d{1,}\Z/
					print_dry_run @instances_interface.dry.get(args[0].to_i)
				else
					print_dry_run @instances_interface.dry.get({name:args[0]})
				end
				return
			end
			instance = find_instance_by_name_or_id(args[0])
			json_response = @instances_interface.get(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			instance = json_response['instance']
			stats = json_response['stats'] || {}
			# load_balancers = stats = json_response['loadBalancers'] || {}

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

			print "\n" ,cyan, bold, "Instance Details\n","==================", reset, "\n\n"
			print cyan
			puts "ID: #{instance['id']}"
			puts "Name: #{instance['name']}"
			puts "Description: #{instance['description']}"
			puts "Group: #{instance['group'] ? instance['group']['name'] : ''}"
			puts "Cloud: #{instance['cloud'] ? instance['cloud']['name'] : ''}"
			puts "Type: #{instance['instanceType']['name']}"
			puts "Plan: #{instance['plan'] ? instance['plan']['name'] : ''}"
			puts "Environment: #{instance['instanceContext']}"
			puts "Nodes: #{instance['containers'] ? instance['containers'].count : 0}"
			puts "Connection: #{connection_string}"
			#puts "Account: #{instance['account'] ? instance['account']['name'] : ''}"
			puts "Status: #{status_string}"
			
			if ((stats['maxMemory'].to_i != 0) || (stats['maxStorage'].to_i != 0))
				print "\n"
				stats_map = {}
				stats_map[:memory] = "#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}"
				stats_map[:storage] = "#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}"
				stats_map[:cpu] = "#{stats['usedCpu'].to_f.round(2)}%"
				tp [stats_map], :memory,:storage,:cpu
			end
			print reset, "\n"

			#puts instance
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def backups(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			params = {}
			if options[:dry_run]
				print_dry_run @instances_interface.dry.backups(instance['id'], params)
				return
			end
			json_response = @instances_interface.backups(instance['id'], params)
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			backups = json_response['backups']
			stats = json_response['stats'] || {}
			# load_balancers = stats = json_response['loadBalancers'] || {}

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

			print "\n" ,cyan, bold, "Instance Backups\n","==================", reset, "\n\n"
			print cyan
			puts "ID: #{instance['id']}"
			puts "Name: #{instance['name']}"
			print "\n"
			puts "Backups:"
			backup_rows = backups.collect {|it| {id: it['id'], name: it['name'], dateCreated: it['dateCreated']} }
			print cyan
			tp backup_rows, [
				:id,
				:name,
				{:dateCreated => {:display_name => "Date Created"} }
			]
			print reset, "\n"
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def envs(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.get_envs(instance['id'])
				return
			end
			json_response = @instances_interface.get_envs(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			print "\n" ,cyan, bold, "#{instance['name']} (#{instance['instanceType']['name']})\n","==================", "\n\n", reset, cyan
			envs = json_response['envs'] || {}
			if json_response['readOnlyEnvs']
				envs += json_response['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value'], :export => true}}
			end
			tp envs, :name, :value, :export
			print "\n" ,cyan, bold, "Imported Envs\n","==================", "\n\n", reset, cyan
			 imported_envs = json_response['importedEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value']}}
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
			opts.banner = subcommand_usage("[name] VAR VALUE [-e]")
			opts.on( '-e', "Exportable" ) do |exportable|
				options[:export] = exportable
			end
			opts.on( '-M', "Masked" ) do |masked|
				options[:masked] = masked
			end
			build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
		end
		if args.count < 3
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			evar = {name: args[1], value: args[2], export: options[:export], masked: options[:masked]}
			payload = {envs: [evar]}
			if options[:dry_run]
				print_dry_run @instances_interface.dry.create_env(instance['id'], payload)
				return
			end
			json_response = @instances_interface.create_env(instance['id'], payload)
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			if !options[:quiet]
				envs([args[0]])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def delenv(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] VAR")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 2
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.del_env(instance['id'], args[1])
				return
			end
			json_response = @instances_interface.del_env(instance['id'], args[1])
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			if !options[:quiet]
				envs([args[0]])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def stop(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop this instance?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.stop(instance['id'])
				return
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.start(instance['id'])
				return
			end
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart this instance?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.restart(instance['id'])
				return
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

	def suspend(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to suspend this instance?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.suspend(instance['id'])
				return
			end
			json_response = @instances_interface.suspend(instance['id'])
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

	def eject(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("restart [name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to eject this instance?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.eject(instance['id'])
				return
			end
			json_response = @instances_interface.eject(instance['id'])
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop this instance?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.stop(instance['id'],false)
				return
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.start(instance['id'], false)
				return
			end
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart this instance?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.restart(instance['id'],false)
				return
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])

			group_id = instance['group']['id']
			cloud_id = instance['cloud']['id']
			layout_id = instance['layout']['id']

			plan_id = instance['plan']['id']
			payload = {
				:instance => {:id => instance["id"]}
			}

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
			#payload[:servicePlanId] = new_plan_id
			payload[:instance][:plan] = {id: service_plan["id"]}

			volumes_response = @instances_interface.volumes(instance['id'])
			current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

			# prompt for volumes
			volumes = prompt_resize_volumes(current_volumes, service_plan, options)
			if !volumes.empty?
				payload[:volumes] = volumes
			end

			# only amazon supports this option
			# for now, always do this
			payload[:deleteOriginalVolumes] = true

			if options[:dry_run]
				print_dry_run @instances_interface.dry.resize(instance['id'], payload)
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
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1 
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to backup the instance '#{instance['name']}'?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.backup(instance['id'])
				return
			end
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
			opts.banner = subcommand_usage()
			opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
				options[:group] = val
			end
			opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
				options[:cloud] = val
			end
			build_common_options(opts, options, [:list, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		connect(options)
		begin
			params = {}
			group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
			if group
				params['siteId'] = group['id']
			end

			# argh, this doesn't work because group_id is required for options/clouds
			# cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
			cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
			if cloud
				params['zoneId'] = cloud['id']
			end

			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			if options[:dry_run]
				print_dry_run @instances_interface.dry.list(params)
				return
			end
			json_response = @instances_interface.get(params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				instances = json_response['instances']

				title = "Morpheus Instances"
				subtitles = []
				if group
					subtitles << "Group: #{group['name']}".strip
				end
				if cloud
					subtitles << "Cloud: #{cloud['name']}".strip
				end
				if params[:phrase]
					subtitles << "Search: #{params[:phrase]}".strip
				end
				subtitle = subtitles.join(', ')
				print "\n" ,cyan, bold, title, (subtitle.empty? ? "" : " - #{subtitle}"), "\n", "==================", reset, "\n\n"
				if instances.empty?
					puts yellow,"No instances found.",reset
				else
					print_instances_table(instances)
					print_results_pagination(json_response)
				end
				print reset,"\n"
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
			opts.banner = subcommand_usage("[name] [-fB]")
			opts.on( '-f', '--force', "Force Remove" ) do
				query_params[:force] = 'on'
			end
			opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
				query_params[:keepBackups] = 'on'
			end
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])

		end
		if args.count < 1
			puts "\n#{optparse}\n\n"
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the instance '#{instance['name']}'?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @instances_interface.dry.destroy(instance['id'],query_params)
				return
			end
			json_response = @instances_interface.destroy(instance['id'],query_params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			elsif !options[:quiet]
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_disable(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.firewall_disable(instance['id'])
				return
			end
			json_response = @instances_interface.firewall_disable(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			elsif !options[:quiet]
				security_groups([args[0]])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_enable(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.firewall_enable(instance['id'])
				return
			end
			json_response = @instances_interface.firewall_enable(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			elsif !options[:quiet]
				security_groups([args[0]])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def security_groups(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @instances_interface.dry.security_groups(instance['id'])
				return
			end
			json_response = @instances_interface.security_groups(instance['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			securityGroups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups for Instance: #{instance['name']}\n","==================", reset, "\n\n"
			print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
			if securityGroups.empty?
				puts yellow,"No security groups currently applied.",reset
			else
				securityGroups.each do |securityGroup|
					print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
				end
			end
			print reset,"\n"

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def apply_security_groups(args)
		options = {}
		security_group_ids = nil
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [-S] [-c]")
			opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
				security_group_ids = secgroups.split(",")
				clear_or_secgroups_specified = true
			end
			opts.on( '-c', '--clear', "Clear all security groups" ) do
				security_group_ids = []
				clear_or_secgroups_specified = true
			end
			build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		if !clear_or_secgroups_specified 
			puts optparse
			exit
		end
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			payload = {securityGroupIds: security_group_ids}
			if options[:dry_run]
				print_dry_run @instances_interface.dry.apply_security_groups(instance['id'], payload)
				return
			end
			json_response = @instances_interface.apply_security_groups(instance['id'], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			if !options[:quiet]
				security_groups([args[0]])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end


	def run_workflow(args)
		options = {}
		
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [workflow] [options]")
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		if args.count < 2
			puts "\n#{optparse}\n\n"
			exit 1
		end
		
		optparse.parse!(args)
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
			puts optparse
			option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
			puts "\nAvailable Options:\n#{option_lines}\n\n"
			exit 1
		end

		workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
		begin
			if options[:dry_run]
				print_dry_run @instances_interface.dry.workflow(instance['id'],workflow['id'], workflow_payload)
				return
			end
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

	def import_snapshot(args)
		options = {}
		storage_provider_id = nil
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			opts.on("--storage-provider ID", String, "Optional storage provider") do |val|
				storage_provider_id = val
			end
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)
		connect(options)
		begin
			instance = find_instance_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to import a snapshot of the instance '#{instance['name']}'?", options)
				exit 1
			end

			payload = {}

			# Prompt for Storage Provider, use default value.
			begin
				options[:options] ||= {}
				options[:options]['storageProviderId'] = storage_provider_id if storage_provider_id
				storage_provider_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.'}], options[:options], @api_client, {})
				if !storage_provider_prompt['storageProviderId'].empty?
					payload['storageProviderId'] = storage_provider_prompt['storageProviderId']
				end
			rescue RestClient::Exception => e
				puts "Failed to load storage providers"
				#print_rest_exception(e, options)
				exit 1
			end

			if options[:dry_run]
				print_dry_run @instances_interface.dry.import_snapshot(instance['id'], payload)
				return
			end
			json_response = @instances_interface.import_snapshot(instance['id'], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Snapshot import initiated."
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private 
	
	def find_zone_by_name_or_id(group_id, val)
		zone = nil
		if val.to_s =~ /\A\d{1,}\Z/
			json_results = @clouds_interface.get(val.to_i)
			zone = json_results['zone']
			if zone.nil?
				print_red_alert "Cloud not found by id #{val}"
				exit 1
			end
		else
			json_results = @clouds_interface.get({groupId: group_id, name: val})
			zone = json_results['zones'] ? json_results['zones'][0] : nil
			if zone.nil?
				print_red_alert "Cloud not found by name #{val}"
				exit 1
			end
		end
		return zone
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

	def print_instances_table(instances, opts={})
		table_color = opts[:color] || cyan
		rows = instances.collect do |instance|
			status_string = instance['status']
			if status_string == 'running'
				status_string = "#{green}#{status_string.upcase}#{table_color}"
			elsif status_string == 'stopped' or status_string == 'failed'
				status_string = "#{red}#{status_string.upcase}#{table_color}"
			elsif status_string == 'unknown'
				status_string = "#{white}#{status_string.upcase}#{table_color}"
			else
				status_string = "#{yellow}#{status_string.upcase}#{table_color}"
			end
			connection_string = ''
			if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
				connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
			end
			{
				id: instance['id'], 
				name: instance['name'], 
				connection: connection_string, 
				environment: instance['instanceContext'], 
				nodes: instance['containers'].count, 
				status: status_string, 
				type: instance['instanceType']['name'], 
				group: !instance['group'].nil? ? instance['group']['name'] : nil, 
				cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil
			}
		end

		print table_color
		tp rows, :id, :name, :group, :cloud, :type, :environment, :nodes, :connection, :status
		print reset
	end

end
