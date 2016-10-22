require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::AppTemplates
  include Morpheus::Cli::CliCommand
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
		@app_templates_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).app_templates
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
	end

	def handle(args)
		usage = "Usage: morpheus app-templates [list,details,add,update,remove,add-instance,remove-instance,connect-tiers,available-tiers] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
			exit 1
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
      when 'add-instance'
        add_instance(args[1..-1])
      when 'remove-instance'
        remove_instance(args[1..-1])
      when 'connect-tiers'
        connect_tiers(args[1..-1])
			when 'remove'
				remove(args[1..-1])
      when 'available-tiers'
        available_tiers(args[1..-1])
      when 'available-types'
        available_types(args[1..-1])
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse(args)
		connect(options)
		begin
      params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @app_templates_interface.list(params)
			app_templates = json_response['appTemplates']
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus App Templates\n","==================", reset, "\n\n"
				if app_templates.empty?
					puts yellow,"No app templates found.",reset
				else
					print_app_templates_table(app_templates)
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
		usage = "Usage: morpheus app-templates details [name]"
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
      opts.on( '-c', '--config', "Display Config Data" ) do |val|
        options[:config] = true
      end
      build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
    if args.count < 1
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]
		connect(options)
		begin
	
			app_template = find_app_template_by_name(name)
			exit 1 if app_template.nil?

			json_response = @app_templates_interface.get(app_template['id'])
			app_template = json_response['appTemplate']

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "App Template Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{app_template['id']}"
				puts "Name: #{app_template['name']}"
				#puts "Category: #{app_template['category']}"
				puts "Account: #{app_template['account'] ? app_template['account']['name'] : ''}"
        instance_type_names = (app_template['instanceTypes'] || []).collect {|it| it['name'] }
        #puts "Instance Types: #{instance_type_names.join(', ')}"
        config = app_template['config']['tierView']
        tiers = config['nodes'].select {|node| node['data']['type'] == "tier" }
        if tiers.empty?
          puts yellow,"0 Tiers",reset
        else
          tiers.each do |tier|
            instances = config['nodes'].select {|node| node['data']['type'] == "instance" && node['data']['parent'] == tier['data']['id'] }.sort {|x,y| x['data']['index'].to_i <=> y['data']['index'].to_i }
            print "\n"
            print cyan, "=  #{tier['data']['name']}\n"
            instances.each do |instance|
              instance_id = instance['data']['id'].sub('newinstance-', '')
              print green, "     - #{instance['data']['typeName']} (#{instance_id})\n",reset
            end

          end
        end
        print cyan

        if options[:config]
          puts "\nConfig:"
          puts JSON.pretty_generate(config)
        end

				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		usage = "Usage: morpheus app-templates add"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      # opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
      #   options[:options] ||= {}
      #   options[:options]['group'] = group
      # end
      build_common_options(opts, options, [:options, :json])
    end
    optparse.parse(args)
    connect(options)
    begin
  
      params = Morpheus::Cli::OptionTypes.prompt(add_app_template_option_types, options[:options], @api_client, options[:params])

      #puts "parsed params is : #{params.inspect}"
      app_template_keys = ['name']
      app_template_payload = params.select {|k,v| app_template_keys.include?(k) }
      
      group = nil
      if params['group'].to_s != ''
        group = find_group_by_name(params['group'])
        exit 1 if group.nil?
        #app_template_payload['siteId'] = {id: group['id']}
      end
      config = {
        nodes: []
      }
      request_payload = {appTemplate: app_template_payload}
      request_payload['siteId'] = group['id'] if group
      request_payload['config'] = config
      json_response = @app_templates_interface.create(request_payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added app template #{app_template_payload['name']}"
        details_options = [app_template_payload["name"]]
        details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
	end

	def update(args)
		usage = "Usage: morpheus app-templates update [name] [options]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:options, :json])
    end
    optparse.parse(args)

    if args.count < 1
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]

    connect(options)
    
    begin

      app_template = find_app_template_by_name(name)
      exit 1 if app_template.nil?

      #params = Morpheus::Cli::OptionTypes.prompt(update_app_template_option_types, options[:options], @api_client, options[:params])
      params = options[:options] || {}

      if params.empty?
        puts "\n#{usage}\n\n"
        option_lines = update_app_template_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      app_template_keys = ['name']
      app_template_payload = params.select {|k,v| app_template_keys.include?(k) }
      
      group = nil
      if params['group'].to_s != ''
        group = find_group_by_name(params['group'])
        exit 1 if group.nil?
        #app_template_payload['siteId'] = {id: group['id']}
      end
      config = app_template['config'] # {}
      request_payload = {appTemplate: app_template_payload}
      if group
        request_payload['siteId'] = group['id']
      else
        request_payload['siteId'] = app_template['config']['siteId']
      end
      # request_payload['config'] = config['tierView']
      request_payload['config'] = config
      json_response = @app_templates_interface.update(app_template['id'], request_payload)

      
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated app template #{app_template_payload['name']}"
        details_options = [app_template_payload["name"] || app_template['name']]
        details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
	end

  def remove(args)
    usage = "Usage: morpheus app-templates remove [name]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:auto_confirm, :json])
    end
    optparse.parse(args)

    if args.count < 1
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]

    connect(options)
    begin
      # allow finding by ID since name is not unique!
      app_template = ((name.to_s =~ /\A\d{1,}\Z/) ? find_app_template_by_id(name) : find_app_template_by_name(name) )
      exit 1 if app_template.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the app template #{app_template['name']}?")
        exit
      end
      json_response = @app_templates_interface.destroy(app_template['id'])
      
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "App Template #{app_template['name']} removed"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_instance(args)
    usage = "Usage: morpheus app-templates add-instance [name] [tier] [instance-type]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      # opts.on( '-g', '--group GROUP', "Group" ) do |val|
      #   options[:group] = val
      # end
      # opts.on( '-c', '--cloud CLOUD', "Cloud" ) do |val|
      #   options[:cloud] = val
      # end
      build_common_options(opts, options, [:json])
    end
    optparse.parse(args)

    if args.count < 3
      puts "\n#{optparse}\n\n"
      exit 1
    end

    connect(options)

    name = args[0]
    tier_name = args[1]
    instance_type_code = args[2]

    app_template = find_app_template_by_name(name)
    exit 1 if app_template.nil?

    instance_type = find_instance_type_by_code(instance_type_code)
    if instance_type.nil?
      exit 1
    end

    groupId = app_template['config']['siteId']
    # groupId = nil
    # if !options[:group].nil?
    #   group = find_group_by_name(options[:group])
    #   if !group.nil?
    #     groupId = group
    #   end
    # else
    #   groupId = @active_groups[@appliance_name.to_sym]  
    # end

    if groupId.nil?
      #puts "Group not found or specified! \n #{optparse}"
      print_red_alert("Group not found or specified for this template!")
      puts "#{optparse}"
      exit 1
    end

    cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'optionSource' => 'clouds', 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: groupId})
    cloud = cloud_prompt['cloud']

    # if options[:cloud].nil?
    #   #puts "Cloud not specified! \n #{optparse}"
    #   print_red_alert("Cloud not specified!")
    #   puts "#{optparse}"
    #   exit 1
    # end
    # cloud = find_cloud_by_name(groupId,options[:cloud])
    # if cloud.nil?
    #   #puts "Cloud not found! \n #{optparse}"
    #   #print_red_alert("Cloud not found!")
    #   puts "#{optparse}"
    #   exit 1
    # end


    instance_option_types = [{'fieldName' => 'name', 'fieldLabel' => 'Instance Name', 'type' => 'text'}]
    instance_option_values = Morpheus::Cli::OptionTypes.prompt(instance_option_types, options[:options], @api_client, options[:params])
    instance_name = instance_option_values['name'] || ''

    # copied from instances command, this payload isn't used
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
      puts "Checking for option Types"
      provision_payload = Morpheus::Cli::OptionTypes.prompt(layout['provisionType']['optionTypes'],options[:options],@api_client,{groupId: groupId, cloudId: cloud, zoneId: cloud, instanceTypeId: instance_type['id'], version: version_prompt['version']})
    end

    if !provision_payload.nil? && !provision_payload['config'].nil?
      payload.merge!(provision_payload['config'])
    end
    # if !provision_payload.nil? && !provision_payload['server'].nil?
    #   payload[:server] = provision_payload['server']
    # end


    config = app_template['config']['tierView']

    config['nodes'] ||= []

    tier = config['nodes'].find {|node| 
      node["data"] && node["data"]["type"] == "tier" && node["data"]["id"] == "newtier-#{tier_name}"
    }
    if !tier
      tier = {
        "classes"=>"tier newtier-#{tier_name}", 
        "data"=>{"id"=>"newtier-#{tier_name}", "name"=> tier_name, "type"=>"tier"}, 
        "grabbable"=>true, "group"=>"nodes","locked"=>false, 
        #"position"=>{"x"=>-2.5, "y"=>-45}, 
        "removed"=>false, "selectable"=>true, "selected"=>false
      }
      config['nodes'] << tier
    end
    
    instance_id = generate_id()

    instance_type_node = {
      "classes"=>"instance newinstance-#{instance_id} #{instance_type['code']}", 
      "data"=>{
        "controlName" => "instance.layout.id",
        "id"=>"newinstance-#{instance_id}", 
        "nodeId"=>["newinstance-#{instance_id}"], # not sure what this is for..
        "index"=>nil, 
        "instance.layout.id"=>layout_id.to_s,
        "instance.name"=>instance_name, 
        "instanceType"=>instance_type['code'], 
        "isPlaced"=>true, 
        "name"=> instance_name, 
        "parent"=>tier['data']['id'], 
        "type"=>"instance", 
        "typeName"=>instance_type['name'],
        "servicePlan"=>plan_prompt['servicePlan'].to_s,
        # "servicePlanOptions.maxCpu": "",
        # "servicePlanOptions.maxCpuId": nil,
        # "servicePlanOptions.maxMemory": "",
        # "servicePlanOptions.maxMemoryId": nil,
        
        # "volumes.datastoreId": nil,
        # "volumes.name": "root",
        # "volumes.rootVolume": "true",
        # "volumes.size": "5",
        # "volumes.sizeId": "5",
        # "volumes.storageType": nil,

        "version"=>version_prompt['version'],
        "siteId"=>groupId.to_s,
        "zoneId"=>cloud.to_s
      }, 
      "grabbable"=>true, "group"=>"nodes", "locked"=>false, 
      #"position"=>{"x"=>-79.83254449505226, "y"=>458.33806818181824}, 
      "removed"=>false, "selectable"=>true, "selected"=>false
    }

    if !type_payload['config'].nil?
      instance_type_node['data'].merge!(type_payload['config'])
    end

    if !provision_payload.nil? && !provision_payload['config'].nil?
      instance_type_node['data'].merge!(provision_payload['config'])
    end

    config['nodes'].push(instance_type_node)

    # re-index nodes for this tier
    tier_instances = config['nodes'].select {|node| node['data']['parent'] == tier['data']['id'] }
    tier_instances.each_with_index do |node, idx| 
      node['data']['index'] = idx
    end

    request_payload = {appTemplate: {} }
    request_payload['siteId'] = app_template['config']['siteId']
    # request_payload['config'] = config['tierView']
    request_payload['config'] = config

    begin
      json_response = @app_templates_interface.update(app_template['id'], request_payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added instance type to app template #{app_template['name']}"
        details_options = [app_template['name']]
        details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
    
  end

  def remove_instance(args)
    usage = "Usage: morpheus app-templates remove-instance [name] [instance-id]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:auto_confirm, :json])
    end
    optparse.parse(args)

    if args.count < 2
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]
    instance_id = args[1]

    connect(options)
    
    begin

      app_template = find_app_template_by_name(name)
      exit 1 if app_template.nil?

      config = app_template['config']['tierView']      

      config['nodes'] ||= []

      instance_node = config['nodes'].find { |node| 
        node["data"] && node["data"]["type"] == "instance" && node["data"]["id"] == "newinstance-#{instance_id}"
      }
      
      if instance_node.nil?
        print_red_alert "Instance not found by id #{instance_id}"
        exit 1
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the app template #{instance_node['data']['typeName']} instance #{instance_id}?")
        exit
      end

      tier = config['nodes'].find {|node| 
        node["data"] && node["data"]["type"] == "tier" && node["data"]["id"] == instance_node['data']['parent']
      }

      if tier.nil?
        print_red_alert "Parent Tier not found for instance id #{instance_id}!"
        exit 1
      end

      # remove the one node
      config['nodes'] = config['nodes'].reject {|node|
        node["data"] && node["data"]["type"] == "instance" && node["data"]["id"] == "newinstance-#{instance_id}"
      }
      

      # re-index nodes for this tier
      tier_instances = config['nodes'].select {|node| node['data']['parent'] == tier['data']['id'] }
      tier_instances.each_with_index do |node, idx| 
        node['data']['index'] = idx
      end

      request_payload = {appTemplate: {} }
      request_payload['siteId'] = app_template['config']['siteId']
      # request_payload['config'] = config['tierView']
      request_payload['config'] = config
      json_response = @app_templates_interface.update(app_template['id'], request_payload)

      
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added instance type to app template #{app_template['name']}"
        details_options = [app_template['name']]
        details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def connect_tiers(args)
    usage = "Usage: morpheus app-templates connect-tiers [name] [tier1] [tier2]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:json])
    end
    optparse.parse(args)

    if args.count < 3
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]
    tier1_name = args[1]
    tier2_name = args[2]

    connect(options)
    
    begin

      app_template = find_app_template_by_name(name)
      exit 1 if app_template.nil?

      config = app_template['config']['tierView']      

      config['nodes'] ||= []

      tier1 = config['nodes'].find {|node| 
        node["data"] && node["data"]["type"] == "tier" && node["data"]["id"] == "newtier-#{tier1_name}"
      }
      if tier1.nil?
        print_red_alert "Tier not found by name #{tier1_name}!"
        exit 1
      end

      tier2 = config['nodes'].find {|node| 
        node["data"] && node["data"]["type"] == "tier" && node["data"]["id"] == "newtier-#{tier2_name}"
      }
      if tier2.nil?
        print_red_alert "Tier not found by name #{tier2_name}!"
        exit 1
      end
      
      config['edges'] ||= []

      found_edge = config['edges'].find {|edge|
        (edge['data']['source'] == "newtier-#{tier1_name}" && edge['data']['target'] == "newtier-#{tier2_name}") &&
        (edge['data']['target'] == "newtier-#{tier2_name}" && edge['data']['source'] == "newtier-#{tier1_name}")
      }

      if found_edge
        puts yellow,"Tiers #{tier1_name} and #{tier2_name} are already connected.",reset
        exit
      end

      # not sure how this id is being generated in the ui exactly
      new_edge_index = (1..999).find {|i|
        !config['edges'].find {|edge| edge['data']['id'] == "ele#{i}" }
      }      
      new_edge = {
        "classes"=>"", 
        "data"=>{"id"=>"ele#{new_edge_index}", "source"=>tier1['data']['id'], "target"=>tier2['data']['id']}, 
        "grabbable"=>true, "group"=>"edges", "locked"=>false, 
        #"position"=>{}, 
        "removed"=>false, "selectable"=>true, "selected"=>false
      }

      config['edges'].push(new_edge)


      request_payload = {appTemplate: {} }
      request_payload['siteId'] = app_template['config']['siteId']
      # request_payload['config'] = config['tierView']
      request_payload['config'] = config
      json_response = @app_templates_interface.update(app_template['id'], request_payload)

      
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Connected tiers for app template #{app_template['name']}"
        details_options = [app_template['name']]
        details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def available_tiers(args)
    options = {}
    optparse = OptionParser.new do|opts|
      build_common_options(opts, options, [:json])
    end
    optparse.parse(args)
    connect(options)
    params = {}
  
    begin
      json_response = @app_templates_interface.list_tiers(params)
      tiers = json_response['tiers']
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print "\n" ,cyan, bold, "Tiers\n","==================", reset, "\n\n"
        if tiers.empty?
          puts yellow,"No tiers found.",reset
        else
          rows = tiers.collect do |tier|
            {
              id: tier['id'], 
              name: tier['name'], 
            }
          end
          print cyan
          tp rows, [:name]
          print reset
        end
        print reset,"\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
    
  end

  def available_types(args)
    options = {}
    optparse = OptionParser.new do|opts|
      build_common_options(opts, options, [:json])
    end
    optparse.parse(args)
    connect(options)
    params = {}
  
    begin
      json_response = @app_templates_interface.list_types(params)
      instance_types = json_response['types']
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print "\n" ,cyan, bold, "Instance Types\n","==================", reset, "\n\n"
        if instance_types.empty?
          puts yellow,"No instance types found.",reset
        else
          rows = instance_types.collect do |instance_type|
            {
              id: instance_type['id'], 
              code: instance_type['code'], 
              name: instance_type['name'], 
            }
          end
          print cyan
          tp rows, [:code, :name]
          print reset
        end
        print reset,"\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
    
  end

private
	

	def add_app_template_option_types
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
		]
	end

	def update_app_template_option_types
		add_app_template_option_types
	end

	def find_app_template_by_id(id)
    begin
      json_response = @app_templates_interface.get(id.to_i)
      return json_response['appTemplate']
    rescue RestClient::Exception => e
      if e.response.code == 404
        print_red_alert "App Template not found by id #{id}"
      else
        raise e
      end
    end
  end

	def find_app_template_by_name(name)
    app_templates = @app_templates_interface.list({name: name.to_s})['appTemplates']
    if app_templates.empty?
      print_red_alert "App Template not found by name #{name}"
      return nil
    elsif app_templates.size > 1
      print_red_alert "#{app_templates.size} app templates by name #{name}"
      print_app_templates_table(app_templates, {color: red})
      print reset,"\n\n"
      return nil
    else
      return app_templates[0]
    end
  end

  def find_group_by_name(name)
    group_results = @groups_interface.get(name)
    if group_results['groups'].empty?
      print_red_alert "Group not found by name #{name}"
      return nil
    end
    return group_results['groups'][0]
  end

  def find_cloud_by_name(groupId,name)
    option_results = @options_interface.options_for_source('clouds',{groupId: groupId})
    match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
    if match.nil?
      print_red_alert "Cloud not found by name #{name}"
      return nil
    else
      return match['value']
    end
  end

  def find_instance_type_by_code(code)
    results = @instance_types_interface.get({code: code})
    if results['instanceTypes'].empty?
      print_red_alert "Instance Type not found by code #{code}"
      return nil
    end
    return results['instanceTypes'][0]
  end

  def find_instance_type_by_name(name)
    results = @instance_types_interface.get({name: name})
    if results['instanceTypes'].empty?
      print_red_alert "Instance Type not found by name #{name}"
      return nil
    end
    return results['instanceTypes'][0]
  end

	def print_app_templates_table(app_templates, opts={})
    table_color = opts[:color] || cyan
    rows = app_templates.collect do |app_template|
    	instance_type_names = (app_template['instanceTypes'] || []).collect {|it| it['name'] }.join(', ')
      {
        id: app_template['id'], 
        name: app_template['name'], 
        #code: app_template['code'], 
        instance_types: instance_type_names,
        account: app_template['account'] ? app_template['account']['name'] : nil, 
        #dateCreated: format_local_dt(app_template['dateCreated']) 
      }
    end
    
    print table_color
    tp rows, [
      :id, 
      :name, 
      {:instance_types => {:display_name => "Instance Types"} },
      :account, 
      #{:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end

  def generate_id(len=16)
    id = ""
    len.times { id << (1 + rand(9)).to_s }
    id
  end

end
