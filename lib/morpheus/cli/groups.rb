require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Groups
  include Morpheus::Cli::CliCommand
  
  register_subcommands :list, :details, :add, :use, :unuse, :add_cloud, :remove_cloud, :use, :remove

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		@clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
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
			opts.banner = subcommand_usage("list")
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse!(args)
		connect(options)
		begin
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			json_response = @groups_interface.get(params)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			groups = json_response['groups']
			print "\n" ,cyan, bold, "Morpheus Groups\n","==================", reset, "\n\n"
			if groups.empty?
				puts yellow,"No groups currently configured.",reset
			else
				print_groups_table(groups)
				print_results_pagination(json_response)
			end
			print reset,"\n"
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("details", "[name]")
			build_common_options(opts, options, [:json])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		connect(options)
		begin
			group = find_group_by_name_or_id(args[0])
			#json_response = @groups_interface.get(group['id'])
			json_response = {'group' => group}
			if options[:json]
				print JSON.pretty_generate(json_response)
				return
			end
			group = json_response['group']

			active_group_id = @active_groups[@appliance_name.to_sym]
			is_active = active_group_id && (active_group_id == group['id'])

			print "\n" ,cyan, bold, "Group Details\n","==================", reset, "\n\n"
			print cyan
			puts "ID: #{group['id']}"
			puts "Name: #{group['name']}"
			puts "Location: #{group['location']}"
			puts "Clouds: #{group['zones'].collect {|it| it['name'] }.join(', ')}"
			puts "Hosts: #{group['serverCount']}"
			
			if is_active
				puts "\n => This is the active group."
			end

			print reset,"\n"

			#puts instance
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("add", "[name]")
			opts.on( '-l', '--location LOCATION', "Location" ) do |val|
				params[:location] = val
			end
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		begin
			group = {name: args[0], location: params[:location]}
			payload = {group: group}
			if options[:dry_run]
				print_dry_run("POST #{@appliance_url}/api/groups", payload)
				return
			end
			json_response = @groups_interface.create(payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Added group #{group['name']}"
				list([])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add_cloud(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("add-cloud", "[name]", "CLOUD")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 2
			puts optparse
			exit 1
		end
		connect(options)
		begin
			group = find_group_by_name_or_id(args[0])
			cloud = find_cloud_by_name_or_id(args[1])
			current_zones = group['zones']
			found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
			if found_zone
				print_red_alert "Cloud #{cloud['name']} is already in group #{group['name']}."
				exit 1
			end
			new_zones = current_zones + [{'id' => cloud['id']}]
			payload = {group: {id: group["id"], zones: new_zones}}
			if options[:dry_run]
				print_dry_run("POST #{@appliance_url}/api/groups/#{group['id']}/update-zones", payload)
				return
			end
			json_response = @groups_interface.update_zones(group["id"], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Added cloud #{cloud["id"]} to group #{group['name']}"
				#list([])
				details([group["id"]])
			end			
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove_cloud(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("remove-cloud", "[name]", "CLOUD")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 2
			puts optparse
			exit 1
		end
		connect(options)
		begin
			group = find_group_by_name_or_id(args[0])
			cloud = find_cloud_by_name_or_id(args[1])
			current_zones = group['zones']
			found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
			if !found_zone
				print_red_alert "Cloud #{cloud['name']} is not in group #{group['name']}."
				exit 1
			end
			new_zones = current_zones.reject {|it| it["id"] == cloud["id"] }
			payload = {group: {id: group["id"], zones: new_zones}}
			if options[:dry_run]
				print_dry_run("POST #{@appliance_url}/api/groups/#{group['id']}/update-zones", payload)
				return
			end
			json_response = @groups_interface.update_zones(group["id"], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print_green_success "Removed cloud #{cloud['name']} from group #{group['name']}"
				# list([])
				details([group["id"]])
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("remove", "[name]")
			build_common_options(opts, options, [:auto_confirm])
		end
		optparse.parse!(args)
		connect(options)
		if args.count < 1
			puts optparse
			exit 1
		end

		begin
			group_results = @groups_interface.get(args[0])
			if group_results['groups'].empty?
				print_red_alert "Group not found by name #{args[0]}"
				exit 1
			end
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the group #{group_results['groups'][0]['name']}?")
				exit
			end
			@groups_interface.destroy(group_results['groups'][0]['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def use(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("use", "[name]", "[--none]")
			opts.on('--none','--none', "Do not use an active group.") do |json|
				options[:unuse] = true
			end
			build_common_options(opts, options, [])
		end
		optparse.parse!(args)
		connect(options)
		
		if options[:unuse]
			if @active_groups[@appliance_name.to_sym] 
				@active_groups.delete(@appliance_name.to_sym)
			end
			::Morpheus::Cli::Groups.save_groups(@active_groups)
			unless options[:quiet]
				puts "Switched to no active group."
				puts "You will be prompted for Group during provisioning."
			end
			print reset
			return # exit 0
		end
		
		if args.length == 0
			active_group_id = @active_groups[@appliance_name.to_sym]
			if active_group_id
				active_group = find_group_by_id(active_group_id)
			end
			puts "#{optparse}"
			if active_group
				puts "\n=> You are currently using the group '#{active_group['name']}'\n"
			else
				puts "\nYou are not using any group.\n"
			end
			print reset
			exit 1
		end

		begin
			group = find_group_by_name_or_id(args[0])
			if !group
				print_red_alert "Group not found by name #{args[0]}"
				exit 1
			end
			@active_groups[@appliance_name.to_sym] = group['id']
			::Morpheus::Cli::Groups.save_groups(@active_groups)
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def unuse(args)
		use(args + ['--none'])
	end

	# Provides the current active group information
	def self.active_group
		appliance_name, appliance_url = Morpheus::Cli::Remote.active_appliance
		if !defined?(@@groups)
			@@groups = load_group_file
		end
		return @@groups[appliance_name.to_sym]
	end

	

	def self.load_group_file
		remote_file = groups_file_path
		if File.exist? remote_file
			return YAML.load_file(remote_file)
		else
			{}
		end
	end

	def self.groups_file_path
		home_dir = Dir.home
		morpheus_dir = File.join(home_dir,".morpheus")
		if !Dir.exist?(morpheus_dir)
			Dir.mkdir(morpheus_dir)
		end
		return File.join(morpheus_dir,"groups")
	end

	def self.save_groups(group_map)
		File.open(groups_file_path, 'w') {|f| f.write group_map.to_yaml } #Store
	end

protected
	
	def find_group_by_id(id)
		raise "#{self.class} has not defined @accounts_interface" if @accounts_interface.nil?
    begin
      json_response = @accounts_interface.get(id.to_i)
      return json_response['groups']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Account not found by id #{id}"
      else
        raise e
      end
    end
	end

	def find_group_by_id(id)
		json_results = @groups_interface.get(id.to_i)
		if json_results['group'].empty?
			print_red_alert "Group not found by id #{id}"
			exit 1
		end
		group = json_results['group']
		return group
	end

	def find_group_by_name(name)
		json_results = @groups_interface.get({name: name})
		if json_results['groups'].empty?
			print_red_alert "Group not found by name #{name}"
			exit 1
		end
		group = json_results['groups'][0]
		return group
	end

	def find_group_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_group_by_id(val)
		else
			return find_group_by_name(val)
		end
	end

	def find_cloud_by_id(id)
		json_results = @clouds_interface.get(id.to_i)
		if json_results['zone'].empty?
			print_red_alert "Cloud not found by id #{id}"
			exit 1
		end
		cloud = json_results['zone']
		return cloud
	end

	def find_cloud_by_name(name)
		json_results = @clouds_interface.get({name: name})
		if json_results['zones'].empty?
			print_red_alert "Cloud not found by name #{name}"
			exit 1
		end
		cloud = json_results['zones'][0]
		return cloud
	end

	def find_cloud_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_cloud_by_id(val)
		else
			return find_cloud_by_name(val)
		end
	end

	def print_groups_table(groups, opts={})
		table_color = opts[:color] || cyan
		active_group_id = @active_groups[@appliance_name.to_sym]
		rows = groups.collect do |group|
			is_active = active_group_id && (active_group_id == group['id'])
			{
				active: (is_active ? "=>" : ""), 
				id: group['id'], 
				name: group['name'], 
				location: group['location'], 
				cloud_count: group['zones'] ? group['zones'].size : 0, 
				server_count: group['serverCount']
			}
		end
		columns = [
			{:active => {:display_name => ""}}, 
			{:id => {:width => 10}}, 
			{:name => {:width => 16}}, 
			{:location => {:width => 32}}, 
			{:cloud_count => {:display_name => "Clouds"}}, 
			{:server_count => {:display_name => "Hosts"}}
		]
		print table_color
		tp rows, columns
		print reset
	end

end
