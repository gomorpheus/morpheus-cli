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
		usage = "Usage: morpheus hosts [list,add,remove,logs,start,stop,run-workflow,make-managed,upgrade-agent,server-types] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
			exit 127
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'start'
				start(args[1..-1])
			when 'stop'
				start(args[1..-1])
			when 'run-workflow'
				run_workflow(args[1..-1])	
			when 'upgrade-agent'
				upgrade(args[1..-1])
			when 'logs'
				logs(args[1..-1])	
			when 'server-types'
				server_types(args[1..-1])
			else
				puts "\n#{usage}\n\n"
				exit 127 #Command now foud exit code
		end
	end

	def logs(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus hosts logs [name]"
			build_common_options(opts, options, [:list, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			logs = @logs_interface.server_logs([host['id']], { max: options[:max] || 100, offset: options[:offset] || 0, query: options[:phrase]})
			if options[:json]
				print JSON.pretty_generate(logs)
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

	def server_types(args) 
		options = {zone: args[0]}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus hosts server-types CLOUD"
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		params = {}
		
		zone=nil

		if !options[:zone].nil?
			zone = find_zone_by_name(nil, options[:zone])
		end

		if zone.nil?
			print_red_alert "Cloud not found for a"
			exit 1
		else
			cloud_type = cloud_type_for_id(zone['zoneTypeId'])
		end
		cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true}
		if options[:json]
			print JSON.pretty_generate(cloud_server_types)
			print "\n"
		else
			
			print "\n" ,cyan, bold, "Morpheus Server Types\n","==================", reset, "\n\n"
			if cloud_server_types.nil? || cloud_server_types.empty?
				puts yellow,"No server types found for the selected cloud.",reset
			else
				cloud_server_types.each do |server_type|
					print cyan, "=  #{server_type['code']} - #{server_type['name']}\n"
				end
			end
			print reset,"\n\n"
		end
	end

	def add(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus hosts add"
			opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
				options[:group_name] = val
			end
			opts.on( '-G', '--group-id ID', "Group Id" ) do |val|
				options[:group_id] = val
			end
			opts.on( '-c', '--cloud CLOUD', "Cloud Name" ) do |val|
				options[:cloud_name] = val
			end
			opts.on( '-t', '--type TYPE', "Server Type" ) do |val|
				options[:server_type_code] = val
			end
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		optparse.parse(args)
		connect(options)

		# support old format of `hosts add CLOUD NAME`
		if args[0] && args[0] !~ /\A\-/
			options[:cloud_name] = args[0]
			if args[1] && args[1] !~ /\A\-/
				options[:host_name] = args[1]
			end
		end
		
		# use active group by default
		if !options[:group_name] && !options[:group_id]
			options[:group_id] = @active_groups[@appliance_name.to_sym]
		end

		params = {}

		# Group
		group_id = nil
		group = find_group_from_options(options)
		if group
			group_id = group["id"]
		else
			# print_red_alert "Group not found or specified!"
			# exit 1
			group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => get_available_groups(), 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
			group_id = cloud_prompt['group']
		end

		# Cloud
		cloud_id = nil
		cloud = find_cloud_from_options(group_id, options)
		if cloud
			cloud_id = cloud["id"]
		else
			# print_red_alert "Cloud not specified!"
			# exit 1
			cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => get_available_clouds(group_id), 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group_id})
			cloud_id = cloud_prompt['cloud']
			cloud = find_cloud_by_id(group_id, cloud_id)
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
		plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this server'}],options[:options])
		service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['servicePlan'].to_i }
		# payload[:servicePlan] = plan_prompt['servicePlan']

		# prompt for volumes
		volumes = prompt_volumes(service_plan, options, @api_client, {})
		if !volumes.empty?
			payload[:volumes] = volumes
		end

		# prompt for network interfaces (if supported)
		if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
			begin
				network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], options, @api_client)
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
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "POST #{@appliance_url}/api/servers", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
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
			opts.banner = "Usage: morpheus hosts remove [name] [-f] [-S]"
			opts.on( '-f', '--force', "Force Remove" ) do
				query_params[:force] = 'on'
			end
			opts.on( '-S', '--skip-remove-infrastructure', "Skip removal of underlying cloud infrastructure" ) do
				query_params[:removeResources] = 'off'
			end
			
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		

		begin
			
			server = find_host_by_name_or_id(args[0])
			
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the server '#{server['name']}'?", options)
				exit 1
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

	def list(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus hosts list"
			opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
				options[:group_name] = val
			end
			
			build_common_options(opts, options, [:list, :json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			
			group = find_group_from_options(options)
			if group
				params['site'] = group['id']
			end

			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @servers_interface.get(params)
			servers = json_response['servers']
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus Hosts\n","==================", reset, "\n\n"
				if servers.empty?
					puts yellow,"No hosts currently configured.",reset
				else
					

					server_table =servers.collect do |server|
						power_state = nil
						if server['powerState'] == 'on'
							power_state = "#{green}ON#{cyan}"
						elsif server['powerState'] == 'off'
							power_state = "#{red}OFF#{cyan}"
						else
							power_state = "#{white}#{server['powerState'].upcase}#{cyan}"
						end
						{id: server['id'], name: server['name'], platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A', type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged', status: server['status'], power: power_state}
						# print cyan, "= [#{server['id']}] #{server['name']} - #{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'} (#{server['status']}) Power: ", power_state, "\n"
					end
				end
				print cyan
				tp server_table, :id, :name, :type, :platform, :status, :power
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end


	def start(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus hosts start [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.start(host['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Host #{host[name]} started."
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
			opts.banner = "Usage: morpheus hosts stop [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.stop(host['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Host #{host[name]} stopped."
			end
			return
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def upgrade(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus hosts upgrade [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			host = find_host_by_name_or_id(args[0])
			json_response = @servers_interface.upgrade(host['id'])
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				puts "Host #{host[name]} upgrading..."
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
			opts.banner = "Usage: morpheus hosts run-workflow [HOST] [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 2
			puts "\n#{optparse}\n\n"
			exit 1
		end
		
		optparse.parse(args)
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
			puts "\n#{optparse.banner}\n\n"
			option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
			puts "\nAvailable Options:\n#{option_lines}\n\n"
			exit 1
		end

		workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
		begin
			
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
		results = @servers_interface.get(id.to_i)
		if results['server'].empty?
			print_red_alert "Server not found by id #{id}"
			exit 1
		end
		return results['server']
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

	def find_zone_by_name(group_id, name)
		zone_results = @clouds_interface.get({groupId: group_id, name: name})
		if zone_results['zones'].empty?
			print_red_alert "Cloud not found by name #{name}"
			exit 1
		end
		return zone_results['zones'][0]
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

end
