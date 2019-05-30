require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::CloudResourcePoolsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  #set_command_name :'cloud-resource-pools'
  set_command_name :'resource-pools'

  register_subcommands :list, :get, :add, :update, :remove
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    cloud_id = nil
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List resource pools for a cloud." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud."
    end
    optparse.parse!(args)
    if args.count == 1
      cloud_id = args[0]
    elsif args.count == 0 && cloud_id
      # support -c
    else
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      params.merge!(parse_list_options(options))
      @cloud_resource_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_resource_pools_interface.dry.list(cloud['id'], params)
        return
      end
      json_response = @cloud_resource_pools_interface.list(cloud['id'], params)
      resource_pools = json_response["resourcePools"]
      if options[:json]
        puts as_json(json_response, options, "resourcePools")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "resourcePools")
        return 0
      elsif options[:csv]
        puts records_as_csv(resource_pools, options)
        return 0
      end
      title = "Morpheus Resource Pools - Cloud: #{cloud['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if resource_pools.empty?
        print cyan,"No resource pools found.",reset,"\n"
      else
        rows = resource_pools.collect {|resource_pool| 
          formatted_name = (resource_pool['depth'] && resource_pool['depth'] > 0) ? (('  ' * resource_pool['depth'].to_i) + resource_pool['name'].to_s) : resource_pool['name'].to_s
          row = {
            id: resource_pool['id'],
            # name: resource_pool['name'],
            name: formatted_name,
            type: resource_pool['type'].to_s.capitalize,
            description: resource_pool['description'],
            active: format_boolean(resource_pool['active']),
            status: resource_pool['status'].to_s.upcase,
            visibility: resource_pool['visibility'].to_s.capitalize,
            default: format_boolean(resource_pool['defaultPool']),
            tenants: resource_pool['tenants'] ? resource_pool['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
            # owner: resource_pool['owner'] ? resource_pool['owner']['name'] : ''
          }
          row
        }
        columns = [:id, :name, :active, :default, :visibility, :tenants]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    resource_pool_id = nil
    cloud_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [pool]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a resource pool." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud." + "\n"
                    "[pool] is required. This is the name or id of a resource pool."
    end
    optparse.parse!(args)
    if args.count == 2
      cloud_id = args[0]
      resource_pool_id = args[1]
    elsif args.count == 1 && cloud_id
      resource_pool_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?
      @cloud_resource_pools_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @cloud_resource_pools_interface.dry.get(cloud['id'], resource_pool_id.to_i)
        else
          print_dry_run @cloud_resource_pools_interface.dry.list(cloud['id'], {name:resource_pool_id})
        end
        return
      end
      resource_pool = find_resource_pool_by_name_or_id(cloud['id'], resource_pool_id)
      return 1 if resource_pool.nil?
      json_response = {'resourcePool' => resource_pool}  # skip redundant request
      # json_response = @resource_pools_interface.get(resource_pool['id'])
      resource_pool = json_response['resourcePool']
      if options[:json]
        puts as_json(json_response, options, "resourcePool")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "resourcePool")
        return 0
      elsif options[:csv]
        puts records_as_csv([resource_pool], options)
        return 0
      end

      print_h1 "Resource Pool Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        #"Type" => lambda {|it| it['type'].to_s.capitalize },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Default" => lambda {|it| format_boolean(it['defaultPool']) },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Status" => lambda {|it| it['status'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' }
      }
      print_description_list(description_cols, resource_pool)

       if resource_pool['resourcePermission'].nil?
        #print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if resource_pool['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if resource_pool['resourcePermission']['sites']
          resource_pool['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        group_columns = {
          "GROUP" => 'name',
          "DEFAULT" => lambda {|it| it['default'].nil? ? '' : format_boolean(it['default']) }
        }
        print cyan
        print as_pretty_table(rows, group_columns)
      end

      if resource_pool['resourcePermission'] && resource_pool['resourcePermission']['plans'] && resource_pool['resourcePermission']['plans'].size > 0
        print_h2 "Service Plan Access"
        rows = []
        if resource_pool['resourcePermission']['allPlans']
          rows.push({"name" => 'All'})
        end
        if resource_pool['resourcePermission']['plans']
          resource_pool['resourcePermission']['plans'].each do |plan|
            rows.push(plan)
          end
        end
        # rows = rows.collect do |site|
        #   {plan: site['name'], default: site['default'] ? 'Yes' : ''}
        #   #{group: site['name']}
        # end
        plan_columns = {
          "PLAN" => 'name',
          "DEFAULT" => lambda {|it| it['default'].nil? ? '' : format_boolean(it['default']) }
        }
        print cyan
        print as_pretty_table(rows, plan_columns)
      end

      if resource_pool['tenants'].nil? || resource_pool['tenants'].empty?
        #print "\n", "No tenant permissions found", "\n"
      else
        print_h2 "Tenant Permissions"
        rows = []
        rows = resource_pool['tenants'] || []
        tenant_columns = {
          "TENANT" => 'name',
          "DEFAULT" => lambda {|it| format_boolean(it['defaultTarget']) },
          "IMAGE TARGET" => lambda {|it| format_boolean(it['defaultStore']) }
        }
        print cyan
        print as_pretty_table(rows, tenant_columns)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    cloud_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [pool] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      opts.on( '--name VALUE', String, "Name" ) do |val|
        options['name'] = val
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true'  || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      # opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
      #   if list.size == 1 && list[0] == 'null' # hacky way to clear it
      #     group_defaults_list = []
      #   else
      #     group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      #   end
      # end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a resource pool") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a resource pool." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud."
    end
    optparse.parse!(args)
    if args.count == 2
      cloud_id = args[0]
      options[:name] = args[1]
    elsif args.count == 1 # && cloud_id
      if cloud_id
        options[:name] = args[0]
      else
        cloud_id = args[0]
      end
    else
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end

    connect(options)

    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for resource pool options
        payload = {
          'resourcePool' => {
          }
        }
        
        # allow arbitrary -O options
        payload['resourcePool'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]


        # Name
        if options['name']
          payload['resourcePool']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name'}], options)
          payload['resourcePool']['name'] = v_prompt['name']
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

        # Active
        if options['active'] != nil
          payload['resourcePool']['active'] = options['active']
        else
          payload['resourcePool']['active'] = true
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['resourcePool']['visibility'] = options['visibility']
        else
          payload['resourcePool']['visibility'] = 'private'
        end


        # Config options depend on type (until api returns these as optionTypes)
        zone_type = cloud['zoneType'] ? cloud['zoneType']['code'] : ''
        if zone_type == 'amazon'
          payload['resourcePool']['config'] ||= {}
          # CIDR
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'config', 'fieldName' => 'cidrBlock', 'fieldLabel' => 'CIDR', 'type' => 'text', 'required' => true, 'description' => 'Provide the base CIDR Block to use for this VPC (must be between a /16 and /28 Block)'}], options)
          payload['resourcePool']['config']['cidrBlock'] = v_prompt['config']['cidrBlock']
          # Tenancy
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'config', 'fieldName' => 'tenancy', 'fieldLabel' => 'Tenancy', 'type' => 'select', 'selectOptions' => [{'name' => 'Default', 'value' => 'default'}, {'name' => 'Dedicated', 'value' => 'dedicated'}], 'defaultValue' => 'default'}], options)
          payload['resourcePool']['config']['tenancy'] = v_prompt['config']['tenancy']

        elsif zone_type == 'azure'
          # no options
        elsif zone_type == 'cloudFoundry' || zone_type == 'bluemixCloudFoundry'
          
        elsif zone_type == 'standard'
          # no options
        else
          #raise_command_error "Cloud type '#{zone_type}' does not allow creating resource pools"
        end

      end
      @cloud_resource_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_resource_pools_interface.dry.create(cloud['id'], payload)
        return
      end
      json_response = @cloud_resource_pools_interface.create(cloud['id'], payload)
      if options[:json]
        puts as_json(json_response)
      else
        resource_pool = json_response['resourcePool']
        print_green_success "Created resource pool #{resource_pool['name']}"
        get([cloud['id'].to_s, resource_pool['id'].to_s])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    cloud_id = nil
    resource_pool_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [pool] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
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
      # opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
      #   if list.size == 1 && list[0] == 'null' # hacky way to clear it
      #     group_defaults_list = []
      #   else
      #     group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      #   end
      # end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a resource pool") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a resource pool." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud." + "\n"
                    "[pool] is required. This is the name or id of a resource pool."
    end
    optparse.parse!(args)
    if args.count == 2
      cloud_id = args[0]
      resource_pool_id = args[1]
    elsif args.count == 1 && cloud_id
      resource_pool_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end

    connect(options)

    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      resource_pool = find_resource_pool_by_name_or_id(cloud['id'], resource_pool_id)
      return 1 if resource_pool.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for resource pool options
        payload = {
          'resourcePool' => {
          }
        }
        
        # allow arbitrary -O options
        payload['resourcePool'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      
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

        # Active
        if options['active'] != nil
          payload['resourcePool']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['resourcePool']['visibility'] = options['visibility']
        end

      end
      @cloud_resource_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_resource_pools_interface.dry.update(cloud['id'], resource_pool["id"], payload)
        return
      end
      json_response = @cloud_resource_pools_interface.update(cloud['id'], resource_pool["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        resource_pool = json_response['resourcePool']
        print_green_success "Updated resource pool #{resource_pool['name']}"
        get([cloud['id'].to_s, resource_pool['id'].to_s])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    cloud_id = nil
    resource_pool_id = nil
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [pool]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a resource pool." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud." + "\n"
                    "[pool] is required. This is the name or id of a resource pool."
    end
    optparse.parse!(args)

    if args.count == 2
      cloud_id = args[0]
      resource_pool_id = args[1]
    elsif args.count == 1 && cloud_id
      resource_pool_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end

    connect(options)
    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      resource_pool = find_resource_pool_by_name_or_id(cloud['id'], resource_pool_id)
      return 1 if resource_pool.nil?

      zone_type = cloud['zoneType'] ? cloud['zoneType']['code'] : ''
      if zone_type == ['amazon','azure','cloudFoundry','bluemixCloudFoundry','standard'].include?(zone_type)
      else
        #raise_command_error "Cloud type '#{zone_type}' does not allow deleting resource pools"
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the resource pool: #{resource_pool['name']}?")
        return 9, "aborted command"
      end
      @cloud_resource_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_resource_pools_interface.dry.destroy(cloud['id'], resource_pool["id"], params)
        return
      end
      json_response = @cloud_resource_pools_interface.destroy(cloud['id'], resource_pool["id"], params)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Removed resource pool #{resource_pool['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


  def find_resource_pool_by_name_or_id(cloud_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_resource_pool_by_id(cloud_id, val)
    else
      return find_resource_pool_by_name(cloud_id, val)
    end
  end

  def find_resource_pool_by_id(cloud_id, id)
    begin
      json_response = @cloud_resource_pools_interface.get(cloud_id, id.to_i)
      return json_response['resourcePool']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Resource Pool not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_resource_pool_by_name(cloud_id, name)
    json_response = @cloud_resource_pools_interface.list(cloud_id, {name: name.to_s})
    resource_pools = json_response['resourcePools']
    if resource_pools.empty?
      print_red_alert "Resource Pool not found by name #{name}"
      return nil
    elsif resource_pools.size > 1
      matching_resource_pools = folders.select { |it| it['name'] == name }
      if matching_resource_pools.size == 1
        return matching_resource_pools[0]
      end
      print_red_alert "#{resource_pools.size} resource pools found by name #{name}"
      rows = resource_pools.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      resource_pool = resource_pools[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][resource_pool['id']]
        resource_pool['tenants'] = json_response['tenants'][resource_pool['id']]
      end
      return resource_pool
    end
  end

end
