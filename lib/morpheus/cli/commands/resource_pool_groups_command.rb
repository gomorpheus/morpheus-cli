require 'morpheus/cli/cli_command'

class Morpheus::Cli::ResourcePoolGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'resource-pool-groups'

  register_subcommands :list, :get, :add, :update, :remove
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @resource_pool_groups_interface = @api_client.resource_pool_groups
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List resource pool groups."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @resource_pool_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_pool_groups_interface.dry.list(params)
        return
      end
      json_response = @resource_pool_groups_interface.list(params)
      resource_pool_groups = json_response["resourcePoolGroups"]
      if options[:json]
        puts as_json(json_response, options, "resourcePoolGroups")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "resourcePoolGroups")
        return 0
      elsif options[:csv]
        puts records_as_csv(resource_pool_groups, options)
        return 0
      end
      title = "Morpheus Resource Pool Groups"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if resource_pool_groups.empty?
        print cyan,"No resource pool groups found.",reset,"\n"
      else
        rows = resource_pool_groups.collect {|resource_pool_group| 
          row = {
            id: resource_pool_group['id'],
            name: resource_pool_group['name'],
            description: resource_pool_group['description'],
            pools: resource_pool_group['pools'] ? resource_pool_group['pools'].size : 0,
            active: format_boolean(resource_pool_group['active']),
            visibility: resource_pool_group['visibility'].to_s.capitalize,
            tenants: resource_pool_group['tenants'] ? resource_pool_group['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
          }
          row
        }
        columns = [:id, :name, :description, :pools, :active, :visibility, :tenants]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "resource pool group", :n_label => "resource pool groups"})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[resource-pool-group]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a resource pool group." + "\n" +
                    "[resource-pool-group] is required. This is the name or id of a resource pool group."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [resource-pool-group]\n#{optparse}"
      return 1
    end
    connect(options)
    exit_code, err = 0, nil
    begin
      resource_pool_group_id = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        resource_pool_group_id = args[0].to_i
      else
        resource_pool_group = find_resource_pool_group_by_name(args[0])
        return 1, "Resource Pool Group not found" if resource_pool_group.nil?
        resource_pool_group_id = resource_pool_group['id']
      end
      @resource_pool_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_pool_groups_interface.dry.get(resource_pool_group_id)
        return exit_code, err
      end
      json_response = @resource_pool_groups_interface.get(resource_pool_group_id)
      render_result = render_with_format(json_response, options, 'resourcePoolGroup')
      return exit_code, err if render_result

      resource_pool_group = json_response['resourcePoolGroup']
      pools = json_response['pools'] 

      print_h1 "Resource Pool Group Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Pools" => lambda {|it| it['pools'].size rescue 'n/a' },
        "Active" => lambda {|it| it['active'].to_s.capitalize },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
      }
      print_description_list(description_cols, resource_pool_group)

      if pools.empty?
        # print cyan,"No pools found.",reset,"\n"
      else
        print_h2 "Pools"
        pool_columns = {
          "ID" => 'id',
          "Name" => 'name',
          #"Description" => 'description',
          "Cloud" => lambda {|it| it['zone']['name'] rescue it['zone'] },
          "Default" => lambda {|it| it['defaultPool'] },
          "Active" => lambda {|it| it['active'].to_s.capitalize },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        }
        print cyan
        print as_pretty_table(pools, pool_columns)
        print reset,"\n"
      end

      if resource_pool_group['resourcePermission'].nil?
        print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if resource_pool_group['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if resource_pool_group['resourcePermission']['sites']
          resource_pool_group['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        rows = rows.collect do |site|
          {group: site['name'], default: site['default'] ? 'Yes' : ''}
        end
        columns = [:group, :default]
        print cyan
        print as_pretty_table(rows, columns)
        print reset,"\n"
      end
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  #AC HERE
  def add(args)
    options = {}
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--pools [id,id,id]")
      opts.on('--name VALUE', String, "Name for this resource pool group") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of resource pool group") do |val|
        options['description'] = val
      end
      opts.on('--pools LIST', Array, "Pools in the group, comma separated list of pool names or IDs") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          options['pools'] = []
        else
          options['pools'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_defaults_list = []
        else
          group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--accounts LIST', Array, "alias for --tenants") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a resource pool group") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new resource pool group." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # support [name] as first argument
      if args[0]
        options['name'] = args[0]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for resource pool group options
        payload = {
          'resourcePoolGroup' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['resourcePoolGroup'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['resourcePoolGroup']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this resource pool group.'}], options)
          payload['resourcePoolGroup']['name'] = v_prompt['name']
        end

        # Description
        if options['description']
          payload['resourcePoolGroup']['description'] = options['description']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of resource pool group.'}], options)
          payload['resourcePoolGroup']['description'] = v_prompt['description']
        end
      
        # Pools
        prompt_results = prompt_for_pools(options, options, @api_client)
        if prompt_results[:success]
          payload['resourcePoolGroup']['pools'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1, "Pools prompt failed."
        end
        
        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['resourcePoolGroup']['visibility'] = options['visibility']
        end

        # Active
        if options['active'] != nil
          payload['resourcePoolGroup']['active'] = options['active']
        end

      end

      @resource_pool_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_pool_groups_interface.dry.create(payload)
        return
      end
      json_response = @resource_pool_groups_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        resource_pool_group = json_response['resourcePoolGroup']
        print_green_success "Added resource pool group #{resource_pool_group['name']}"
        get([resource_pool_group['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[resource-pool-group] [options]")
      opts.on('--name VALUE', String, "Name for this resource pool group") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of resource pool group") do |val|
        options['description'] = val
      end
      opts.on('--pools LIST', Array, "Pools in the group, comma separated list of pool IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['pools'] = []
        else
          options['pools'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_defaults_list = []
        else
          group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--accounts LIST', Array, "alias for --tenants") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a resource pool group") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a resource pool group." + "\n" +
                    "[resource-pool-group] is required. This is the id of a resource pool group."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      resource_pool_group = find_resource_pool_group_by_name_or_id(args[0])
      return 1 if resource_pool_group.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for resource pool group options
        payload = {
          'resourcePoolGroup' => {
          }
        }
        
        # allow arbitrary -O options
        payload['resourcePoolGroup'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['resourcePoolGroup']['name'] = options['name']
        end

        # Description
        if options['description']
          payload['resourcePoolGroup']['description'] = options['description']
        end

        # Pools
        if options['pools']
          prompt_results = prompt_for_pools(options, options, @api_client)
          if prompt_results[:success]
            payload['resourcePoolGroup']['pools'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1, "Pools prompt failed."
          end
        end

        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['resourcePoolGroup']['visibility'] = options['visibility']
        end

        # Active
        if options['active'] != nil
          payload['resourcePoolGroup']['active'] = options['active']
        end
        
        # pre 4.2.1, would error with data not found unless you pass something in here
        # so pass foo=bar so you can update just resourcePermissions
        if payload['resourcePoolGroup'] && payload['resourcePoolGroup'].empty? && payload['resourcePermissions']
          payload['resourcePoolGroup']['foo'] = 'bar'
        end

      end
      @resource_pool_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_pool_groups_interface.dry.update(resource_pool_group["id"], payload)
        return
      end
      json_response = @resource_pool_groups_interface.update(resource_pool_group["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        resource_pool_group = json_response['resourcePoolGroup']
        print_green_success "Updated resource pool group #{resource_pool_group['name']}"
        get([resource_pool_group['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[resource-pool-group]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a resource pool group." + "\n" +
                    "[resource-pool-group] is required. This is the name or id of a resource pool group."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [resource-pool-group]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      resource_pool_group = find_resource_pool_group_by_name_or_id(args[0])
      return 1 if resource_pool_group.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the resource pool group: #{resource_pool_group['name']}?")
        return 9, "aborted command"
      end
      @resource_pool_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_pool_groups_interface.dry.destroy(resource_pool_group['id'])
        return 0
      end
      json_response = @resource_pool_groups_interface.destroy(resource_pool_group['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed resource pool group #{resource_pool_group['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


end
