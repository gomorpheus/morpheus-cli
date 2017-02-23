# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Hosts
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
	
	register_subcommands :list, :get, :stats, :add, :remove, :logs, :start, :stop, :resize, :run_workflow, :make_managed, :upgrade_agent, :server_types
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
		@clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
		@options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		@tasks_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).tasks
		@task_sets_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).task_sets
		@servers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).servers
		@logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end

	def handle(args)
    handle_subcommand(args)
  end

  def list(args)
		options = {}
		params = {}
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
				print_dry_run @servers_interface.dry.get(params)
				return
			end
			json_response = @servers_interface.get(params)

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				servers = json_response['servers']
				title = "Morpheus Hosts"
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
				if servers.empty?
					puts yellow,"No hosts found.",reset
				else
					print_servers_table(servers)
					print_results_pagination(json_response)
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
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			if options[:dry_run]
				if args[0].to_s =~ /\A\d{1,}\Z/
					print_dry_run @servers_interface.dry.get(args[0].to_i)
				else
					print_dry_run @servers_interface.dry.get({name: args[0]})
				end
				return
			end
			server = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.get(server['id'])
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			server = json_response['server']
			#stats = server['stats'] || json_response['stats'] || {}
			stats = json_response['stats'] || {}

			print "\n" ,cyan, bold, "Host Details\n","==================", reset, "\n\n"
			print cyan
			puts "ID: #{server['id']}"
			puts "Name: #{server['name']}"
			puts "Description: #{server['description']}"
			puts "Account: #{server['account'] ? server['account']['name'] : ''}"
			#puts "Group: #{server['group'] ? server['group']['name'] : ''}"
			#puts "Cloud: #{server['cloud'] ? server['cloud']['name'] : ''}"
			puts "Cloud: #{server['zone'] ? server['zone']['name'] : ''}"
			puts "Nodes: #{server['containers'] ? server['containers'].size : ''}"
			puts "Type: #{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'}"
			puts "Platform: #{server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A'}"
			puts "Plan: #{server['plan'] ? server['plan']['name'] : ''}"
			puts "Status: #{format_host_status(server)}"
			puts "Power: #{format_server_power_state(server)}"
			if ((stats['maxMemory'].to_i != 0) || (stats['maxStorage'].to_i != 0))
				# stats_map = {}
				print "\n"
				#print "\n" ,cyan, bold, "Host Stats\n","==================", reset, "\n\n"
				# stats_map[:memory] = "#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}"
				# stats_map[:storage] = "#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}"
				# stats_map[:cpu] = "#{stats['cpuUsage'].to_f.round(2)}%"
				# tp [stats_map], :memory,:storage,:cpu
				print_stats_usage(stats)
			else
				#print yellow, "No stat data.", reset
			end

			print reset, "\n"

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
			if options[:dry_run]
				if args[0].to_s =~ /\A\d{1,}\Z/
					print_dry_run @servers_interface.dry.get(args[0].to_i)
				else
					print_dry_run @servers_interface.dry.get({name: args[0]})
				end
				return
			end
			server = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.get(server['id'])
			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end
			server = json_response['server']
			#stats = server['stats'] || json_response['stats'] || {}
			stats = json_response['stats'] || {}

			print "\n" ,cyan, bold, "Host Stats: #{server['name']} (#{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'})\n","==================", "\n\n", reset, cyan
			puts "Status: #{format_host_status(server)}"
			puts "Power: #{format_server_power_state(server)}"
			if ((stats['maxMemory'].to_i != 0) || (stats['maxStorage'].to_i != 0))
				# stats_map = {}
				print "\n"
				#print "\n" ,cyan, bold, "Host Stats\n","==================", reset, "\n\n"
				# stats_map[:memory] = "#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}"
				# stats_map[:storage] = "#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}"
				# stats_map[:cpu] = "#{stats['cpuUsage'].to_f.round(2)}%"
				# tp [stats_map], :memory,:storage,:cpu
				print_stats_usage(stats)
			else
				#print yellow, "No stat data.", reset
			end

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
			build_common_options(opts, options, [:list, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			params[:query] = params.delete(:phrase) unless params[:phrase].nil?
			if options[:dry_run]
				print_dry_run @logs_interface.dry.server_logs([host['id']], params)
				return
			end
			logs = @logs_interface.server_logs([host['id']], params)
			output = ""
			if options[:json]
				output << JSON.pretty_generate(logs)
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
					output << "[#{log_entry['ts']}] #{log_level} - #{log_entry['message']}\n"
				end
			end
			print output, reset, "\n"
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def server_types(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[cloud]")
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		options[:zone] = args[0]
		connect(options)
		params = {}

		zone = find_zone_by_name_or_id(nil, options[:zone])
		cloud_type = cloud_type_for_id(zone['zoneTypeId'])
		cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true}
		cloud_server_types = cloud_server_types.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
		if options[:json]
			print JSON.pretty_generate(cloud_server_types)
			print "\n"
		else
			print "\n" ,cyan, bold, "Morpheus Server Types - Cloud: #{zone['name']}\n","==================", reset, "\n\n"
			if cloud_server_types.nil? || cloud_server_types.empty?
				puts yellow,"No server types found for the selected cloud.",reset
			else
				cloud_server_types.each do |server_type|
					print cyan, "[#{server_type['code']}]".ljust(20), " - ", "#{server_type['name']}", "\n"
				end
			end
			print reset,"\n"
		end
	end

	def add(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[cloud]", "[name]")
			opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
				options[:group] = val
			end
			opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
				options[:cloud] = val
			end
			opts.on( '-t', '--type TYPE', "Server Type Code" ) do |val|
				options[:server_type_code] = val
			end
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		connect(options)

		# support old format of `hosts add CLOUD NAME`
		if args[0]
			options[:cloud] = args[0]
		end
		if args[1]
			options[:host_name] = args[1]
		end
		
		# use active group by default
		options[:group] ||= @active_groups[@appliance_name.to_sym]

		params = {}

		# Group
		group_id = nil
		group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
		if group
			group_id = group["id"]
		else
			# print_red_alert "Group not found or specified!"
			# exit 1
			group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => get_available_groups(), 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
			group_id = group_prompt['group']
		end

		# Cloud
		cloud_id = nil
		cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
		if cloud
			cloud_id = cloud["id"]
		else
			available_clouds = get_available_clouds(group_id)
			if available_clouds.empty?
				print_red_alert "Group #{group['name']} has no available clouds"
				exit 1
			end
			cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => available_clouds, 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group_id})
			cloud_id = cloud_prompt['cloud']
			cloud = find_cloud_by_id_for_provisioning(group_id, cloud_id)
		end

		# Zone Type
		cloud_type = cloud_type_for_id(cloud['zoneTypeId'])

		# Server Type
		cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true }.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
		if options[:server_type_code]
			server_type_code = options[:server_type_code]
		else
			server_type_options = cloud_server_types.collect {|it| {'name' => it['name'], 'value' => it['code']} }
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => "Server Type", 'selectOptions' => server_type_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a server type.'}], options[:options])
			server_type_code = v_prompt['type']
		end
		server_type = cloud_server_types.find {|it| it['code'] == server_type_code }
		if server_type.nil?
			print_red_alert "Server Type #{server_type_code} not found cloud #{cloud['name']}"
			exit 1
		end

		# Server Name
		host_name = nil
		if options[:host_name]
			host_name = options[:host_name]
		else
			name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Server Name', 'type' => 'text', 'required' => true}], options[:options])
			host_name = name_prompt['name'] || ''
		end

		payload = {}
		
		# prompt for service plan
		service_plans_json = @servers_interface.service_plans({zoneId: cloud['id'], serverTypeId: server_type["id"]})
		service_plans = service_plans_json["plans"]
		service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
		plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this server'}],options[:options])
		service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['plan'].to_i }

		# prompt for volumes
		volumes = prompt_volumes(service_plan, options, @api_client, {})
		if !volumes.empty?
			payload[:volumes] = volumes
		end

		# prompt for network interfaces (if supported)
		if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
			begin
				network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], options)
				if !network_interfaces.empty?
					payload[:networkInterfaces] = network_interfaces
				end
			rescue RestClient::Exception => e
				print_yellow_warning "Unable to load network options. Proceeding..."
				print_rest_exception(e, options) if Morpheus::Logging.print_stacktrace?
			end
		end

		server_type_option_types = server_type['optionTypes']
		# remove volume options if volumes were configured
		if !payload[:volumes].empty?
			server_type_option_types = reject_volume_option_types(server_type_option_types)
		end
		# remove networkId option if networks were configured above
		if !payload[:networkInterfaces].empty?
			server_type_option_types = reject_networking_option_types(server_type_option_types)
		end
		# remove cpu and memory option types, which now come from the plan
		server_type_option_types = reject_service_plan_option_types(server_type_option_types)

		params = Morpheus::Cli::OptionTypes.prompt(server_type_option_types,options[:options],@api_client, {zoneId: cloud['id']})
		begin
			params['server'] = params['server'] || {}
			payload = payload.merge({
				server: {
					name: host_name, 
					zone: {id: cloud['id']}, 
					computeServerType: {id: server_type['id']},
					plan: {id: service_plan["id"]}
				}.merge(params['server'])
			})
			payload[:network] = params['network'] if params['network']
			payload[:config] = params['config'] if params['config']
			if options[:dry_run]
				print_dry_run @servers_interface.dry.create(payload)
				return
			end
			json_response = @servers_interface.create(payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Provisioning Server..."
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		query_params = {removeResources: 'on', force: 'off'}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [-f] [-S]")
			opts.on( '-f', '--force', "Force Remove" ) do
				query_params[:force] = 'on'
			end
			opts.on( '-S', '--skip-remove-infrastructure', "Skip removal of underlying cloud infrastructure" ) do
				query_params[:removeResources] = 'off'
			end
			
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		

		begin
			
			server = find_host_by_name_or_id(args[0])
			
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the server '#{server['name']}'?", options)
				exit 1
			end
			if options[:dry_run]
				print_dry_run @servers_interface.dry.destroy(server['id'], query_params)
				return
			end
			json_response = @servers_interface.destroy(server['id'], query_params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Removing Server..."
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def start(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.start(host['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Host #{host['name']} started."
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def stop(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			if options[:dry_run]
				print_dry_run @servers_interface.dry.stop(host['id'])
				return
			end
			json_response = @servers_interface.stop(host['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Host #{host['name']} stopped." unless options[:quiet]
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
			build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			server = find_host_by_name_or_id(args[0])

			group_id = server["siteId"] || erver['group']['id']
			cloud_id = server["zoneId"] || server["zone"]["id"]
			server_type_id = server['computeServerType']['id']
			plan_id = server['plan']['id']
			payload = {
				:server => {:id => server["id"]}
			}

			# avoid 500 error
			# payload[:servicePlanOptions] = {}
			unless options[:no_prompt]
				puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"
				# unless hot_resize
				# 	puts "\nWARNING: Resize actions for this server will cause instances to be restarted.\n\n"
				# end
			end

			# prompt for service plan
			service_plans_json = @servers_interface.service_plans({zoneId: cloud_id, serverTypeId: server_type_id})
			service_plans = service_plans_json["plans"]
			service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
			service_plans_dropdown.each do |plan|
				if plan['value'] && plan['value'].to_i == plan_id.to_i
					plan['name'] = "#{plan['name']} (current)"
				end
			end
			plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this server'}],options[:options])
			service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['plan'].to_i }
			payload[:server][:plan] = {id: service_plan["id"]}

			# fetch volumes
			volumes_response = @servers_interface.volumes(server['id'])
			current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

			# prompt for volumes
			volumes = prompt_resize_volumes(current_volumes, service_plan, options)
			if !volumes.empty?
				payload[:volumes] = volumes
			end

			# todo: reconfigure networks
			#       need to get provision_type_id for network info
			# prompt for network interfaces (if supported)
			# if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
			# 	begin
			# 		network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], options)
			# 		if !network_interfaces.empty?
			# 			payload[:networkInterfaces] = network_interfaces
			# 		end
			# 	rescue RestClient::Exception => e
			# 		print_yellow_warning "Unable to load network options. Proceeding..."
			# 		print_rest_exception(e, options) if Morpheus::Logging.print_stacktrace?
			# 	end
			# end

			# only amazon supports this option
			# for now, always do this
			payload[:deleteOriginalVolumes] = true

			if options[:dry_run]
				print_dry_run @servers_interface.dry.resize(server['id'], payload)
				return
			end
			json_response = @servers_interface.resize(server['id'], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				unless options[:quiet]
					print_green_success "Resizing server #{server['name']}"
					list([])
				end
			end
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def upgrade(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :quiet, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.upgrade(host['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Host #{host['name']} upgrading..." unless options[:quiet]
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def run_workflow(args)
		options = {}
		
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("run-workflow", "[name]", "[workflow]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		if args.count < 2
			puts "\n#{optparse}\n\n"
			exit 1
		end
		
		optparse.parse!(args)
		connect(options)
		host = find_host_by_name_or_id(args[0])
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
				print_dry_run @servers_interface.dry.workflow(host['id'],workflow['id'], workflow_payload)
				return
			end
			json_response = @servers_interface.workflow(host['id'],workflow['id'], workflow_payload)
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

	def find_host_by_id(id)
		begin
      json_response = @servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Host not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
	end

	def find_host_by_name(name)
		results = @servers_interface.get({name: name})
		if results['servers'].empty?
			print_red_alert "Server not found by name #{name}"
			exit 1
		elsif results['servers'].size > 1
			print_red_alert "Multiple Servers exist with the name #{name}. Try using id instead"
			exit 1
		end
		return results['servers'][0]
	end

	def find_host_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_host_by_id(val)
		else
			return find_host_by_name(val)
		end
	end

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

	def find_server_type(zone, name)
		server_type = zone['serverTypes'].select do  |sv_type|
			(sv_type['name'].downcase == name.downcase || sv_type['code'].downcase == name.downcase) && sv_type['creatable'] == true
		end
		if server_type.nil?
			print_red_alert "Server Type Not Selectable"
		end
		return server_type
	end

	def cloud_type_for_id(id)
		cloud_types = @clouds_interface.cloud_types['zoneTypes']
		cloud_type = cloud_types.find { |z| z['id'].to_i == id.to_i}
		if cloud_type.nil?
			print_red_alert "Cloud Type not found by id #{id}"
			exit 1
		end
		return cloud_type
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

	def print_servers_table(servers, opts={})
    table_color = opts[:color] || cyan
    rows = servers.collect do |server|
			{
				id: server['id'], 
				name: server['name'], 
				platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A', 
				cloud: server['zone'] ? server['zone']['name'] : '', 
				type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged', 
				nodes: server['containers'] ? server['containers'].size : '',
				status: format_host_status(server, table_color), 
				power: format_server_power_state(server, table_color)
			}
    end
    columns = [:id, :name, :type, :cloud, :nodes, :status, :power]
    print table_color
    tp rows, columns
    print reset
  end

	def format_server_power_state(server, return_color=cyan)
		out = ""
		if server['powerState'] == 'on'
			out << "#{green}ON#{return_color}"
		elsif server['powerState'] == 'off'
			out << "#{red}OFF#{return_color}"
		else
			out << "#{white}#{server['powerState'].upcase}#{return_color}"
		end
		out
	end

	def format_host_status(server, return_color=cyan)
		out = ""
		status_string = server['status']
		# todo: colorize, upcase?
		out << status_string.to_s
		out
	end

end
