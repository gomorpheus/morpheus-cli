# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::SecurityGroups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :'add-location', :'remove-location'
  register_subcommands :'add-rule', :'update-rule', :'remove-rule'
  set_default_subcommand :list
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @security_groups_interface = @api_client.security_groups
    @security_group_rules_interface = @api_client.security_group_rules
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
    @active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
    @network_security_servers = @api_client.network_security_servers
  end

  def handle(args)
    handle_subcommand(args)
  end


  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List security groups."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.list(params)
        return
      end
      json_response = @security_groups_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'securityGroups')
      return 0 if render_result

      title = "Morpheus Security Groups"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      security_groups = json_response['securityGroups']
      
      if security_groups.empty?
        print cyan,"No security groups found.",reset,"\n"
      else
        active_id = @active_security_group[@appliance_name.to_sym]
        # table_color = options[:color] || cyan
        # rows = security_groups.collect do |security_group|
        #   {
        #     id: security_group['id'].to_s + ((security_group['id'] == active_id.to_i) ? " (active)" : ""),
        #     name: security_group['name'],
        #     description: security_group['description']
        #   }
        # end

        # columns = [
        #   :id,
        #   :name,
        #   :description,
        #   # :ports,
        #   # :status,
        # ]
        columns = {
          "ID" => 'id',
          "NAME" => 'name',
          #"DESCRIPTION" => 'description',
          "DESCRIPTION" => lambda {|it| truncate_string(it['description'], 30) },
          #"USED BY" => lambda {|it| it['associations'] ? it['associations'] : '' },
          "SCOPED CLOUD" => lambda {|it| it['zone'] ? it['zone']['name'] : 'All' },
          "SOURCE" => lambda {|it| it['syncSource'] == 'external' ? 'SYNCED' : 'CREATED' }
        }
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(security_groups, columns, options)
        print reset
        if json_response['meta']
          print_results_pagination(json_response)
        else
          print_results_pagination({'meta'=>{'total'=>(json_response['securityGroupCount'] ? json_response['securityGroupCount'] : security_groups.size),'size'=>security_groups.size,'max'=>(params['max']||25),'offset'=>(params['offset']||0)}})
        end
        # print reset
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
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a security group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    exit_code, err = 0, nil
    
      security_group_id = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        security_group_id = args[0].to_i
      else
        security_group = find_security_group_by_name(args[0])
        return 1, "Security Group not found" if security_group.nil?
        security_group_id = security_group['id']
      end
      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.get(security_group_id)
        return exit_code, err
      end
      json_response = @security_groups_interface.get(security_group_id)
      render_result = render_with_format(json_response, options, 'securityGroup')
      return exit_code, err if render_result

      security_group = json_response['securityGroup']
      security_group_locations = json_response['locations'] || security_group['locations']
      security_group_rules = json_response['rules'] || security_group['rules']

      print_h1 "Security Group Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Scoped Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : 'All' },
        "Source" => lambda {|it| it['syncSource'] == 'external' ? 'SYNCED' : 'CREATED' },
        # "Active" => lambda {|it| format_boolean(it['active']) },
        "Visibility" => 'visibility',
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.sort.join(', ') : '' },
      }
      print_description_list(description_cols, security_group)
      # print reset,"\n"

      if security_group['resourcePermission'].nil?
        #print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if security_group['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if security_group['resourcePermission']['sites']
          security_group['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        rows = rows.collect do |site|
          {group: site['name'], default: site['default'] ? 'Yes' : ''}
        end
        columns = [:group, :default]
        print cyan
        print as_pretty_table(rows, columns)
      end

      if security_group_locations && security_group_locations.size > 0
        print_h2 "Locations"
        print cyan
        location_cols = {
          "ID" => 'id',
          "CLOUD" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
          "EXTERNAL ID" => lambda {|it| it['externalId'] },
          "RESOURCE POOL" => lambda {|it| it['zonePool'] ? it['zonePool']['name'] : '' }
        }
        puts as_pretty_table(security_group_locations, location_cols)
      else
        print reset,"\n"
      end

      if security_group_rules
        if security_group_rules == 0
          #print cyan,"No rules.",reset,"\n"
        else
          print_h2 "Rules"
          print cyan
          # NAME  DIRECTION SOURCE  DESTINATION RULE TYPE PROTOCOL  PORT RANGE
          rule_cols = {
            "ID" => 'id',
            "NAME" => 'name',
            "DIRECTION" => lambda {|it| it['direction'] },
            "SOURCE" => lambda {|it| 
              if it['sourceType'] == 'cidr'
                "Network: #{it['source']}"
              elsif it['sourceType'] == 'group'
                "Group: #{it['sourceGroup'] ? it['sourceGroup']['name'] : ''}"
              elsif it['sourceType'] == 'tier'
                "Tier: #{it['sourceTier'] ? it['sourceTier']['name'] : ''}"
              elsif it['sourceType'] == 'instance'
                "Instance"
              else
                it['sourceType']
              end
            },
            "DESTINATION" => lambda {|it| 
              if it['destinationType'] == 'cidr'
                "Network: #{it['destination']}"
              elsif it['destinationType'] == 'group'
                "Group: #{it['destinationGroup'] ? it['destinationGroup']['name'] : ''}"
              elsif it['destinationType'] == 'tier'
                "Tier: #{it['destinationTier'] ? it['destinationTier']['name'] : ''}"
              elsif it['destinationType'] == 'instance'
                "Instance"
              else
                it['destinationType']
              end
            },
            "RULE TYPE" => lambda {|it| it['ruleType'] == 'customRule' ? 'Custom' : it['ruleType'] },
            "PROTOCOL" => lambda {|it| it['protocol'] },
            "PORT RANGE" => lambda {|it| it['portRange'] }
          }
          puts as_pretty_table(security_group_rules, rule_cols)
        end
      end

      return exit_code, err
  end

  def add(args)
    params = {}
    options = {:options => {}}
    cloud_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on( '--name Name', String, "Name of the security group" ) do |val|
        options[:options]['name'] = val
      end
      opts.on( '--description Description', String, "Description of the security group" ) do |val|
        options[:options]['description'] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Scoped Cloud Name or ID" ) do |val|
        cloud_id = val
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
      opts.on('--can-manage LIST', Array, "Tenant Can Manage, comma separated list of account IDs that can manage") do |list|
        options['canManage'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a security group." + "\n" +
                    "[name] is required. This is the name of the security group."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      options[:options]['name'] = args[0]
    end
    connect(options)
    begin

      # load cloud
      cloud = nil
      if cloud_id
        cloud = find_cloud_by_name_or_id(cloud_id)
        return 1 if cloud.nil?
        options[:options]['zoneId'] = cloud['id'].to_s
      end

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'securityGroup' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'securityGroup' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'securityGroup' => passed_options})  unless passed_options.empty?

        # Name
        options[:options]['name'] = options[:name] if options.key?(:name)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options])
        payload['securityGroup']['name'] = v_prompt['name']

        # Description
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false}], options[:options])
        payload['securityGroup']['description'] = v_prompt['description']

        # Scoped Cloud
        # /api/options/clouds requires groupId...
        
        
        begin
          scoped_clouds = [{"name" => "All", "value" => "all"}]
          clouds_response = @options_interface.options_for_source('cloudsForSecurityGroup',{})
          if clouds_response['data']
            clouds_response['data'].each do |it|
              scoped_clouds << {"name" => it['name'], "value" => it['value']}
            end
          end
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zoneId', 'fieldLabel' => 'Scoped Cloud', 'type' => 'select', 'selectOptions' => scoped_clouds, 'required' => false, 'defaultValue' => (payload['securityGroup']['zoneId'] || 'all')}], options[:options], @api_client)
          #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zoneId', 'fieldLabel' => 'Scoped Cloud', 'type' => 'select', 'optionSource' => 'cloudsForSecurityGroup', 'required' => false}], options[:options], @api_client)
          if !v_prompt['zoneId'].to_s.empty? && v_prompt['zoneId'].to_s != 'all' && v_prompt['zoneId'].to_s != '-1'
            payload['securityGroup']['zoneId'] = v_prompt['zoneId']

            zone = find_cloud_by_id(payload['securityGroup']['zoneId'])
            if zone['securityServer']
              sec_server = @network_security_servers.get(zone['securityServer']['id'])['networkSecurityServer']

              if sec_server['type']
                payload['securityGroup'].deep_merge!(Morpheus::Cli::OptionTypes.prompt(sec_server['type']['optionTypes'], options[:options], @api_client, {zoneId: zone['id']}))
              end
            end
          end
        rescue => ex
          print yellow,"Failed to determine the available scoped clouds.",reset,"\n"
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
        if options['tenants'] || options['canManage']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = ((options['tenants'] || []) + (options['canManage'] || [])).uniq
          payload['tenantPermissions']['canManageAccounts'] = options['canManage'] if options['canManage']
        end

        # Visibility
        if options['visibility'] != nil
          payload['securityGroup']['visibility'] = options['visibility']
        end

        # Active
        if options['active'] != nil
          payload['securityGroup']['active'] = options['active']
        end

      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.create(payload)
        return 0
      end
      json_response = @security_groups_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group #{json_response['securityGroup']['name']}"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    params = {}
    options = {:options => {}}
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      opts.on( '--name Name', String, "Name of the security group" ) do |val|
        options[:options]['name'] = val
      end
      opts.on( '--description Description', String, "Description of the security group" ) do |val|
        options[:options]['description'] = val
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
      opts.on('--can-manage LIST', Array, "Tenant Can Manage, comma separated list of account IDs that can manage") do |list|
        options['canManage'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a security group." + "\n" +
                    "[security-group] is required. This is the name or id of the security group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload['securityGroup'].deep_merge!(passed_options)  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'securityGroup' => {
          }
        }
        # allow arbitrary -O options
        payload['securityGroup'].deep_merge!(passed_options)  unless passed_options.empty?
        
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
        if options['tenants'] || options['canManage']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = ((options['tenants'] || []) + (options['canManage'] || [])).uniq
          payload['tenantPermissions']['canManageAccounts'] = options['canManage'] if options['canManage']
        end

        # Visibility
        if options['visibility'] != nil
          payload['securityGroup']['visibility'] = options['visibility']
        end

        # Active
        if options['active'] != nil
          payload['securityGroup']['active'] = options['active']
        end

        if payload['securityGroup'].empty? && payload['tenantPermissions'].nil? && payload['resourcePermissions'].nil?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.update(security_group['id'], payload)
        return 0
      end
      json_response = @security_groups_interface.update(security_group['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Updated security group #{json_response['securityGroup']['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a security group." + "\n" +
                    "[security-group] is required. This is the name or id of the security group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the security group: #{security_group['name']}?")
        return 9, "aborted command"
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.delete(security_group['id'])
        return
      end
      json_response = @security_groups_interface.delete(security_group['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      #list([])
      print_green_success "Removed security group #{args[0]}"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_location(args)
    cloud_id = nil
    resource_pool_id = nil
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.on( '--resource-pool ID', String, "ID of the Resource Pool for Amazon VPC and Azure Resource Group" ) do |val|
        resource_pool_id = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Add security group to a location (cloud)." + "\n" +
                    "[security-group] is required. This is the name or id of the security group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      if resource_pool_id
        resource_pool = find_resource_pool_by_name_or_id(cloud['id'], resource_pool_id)
        return 1 if resource_pool.nil?
      end

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'securityGroupLocation' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'securityGroupLocation' => {
          }
        }
        payload.deep_merge!({'securityGroupLocation' => passed_options})  unless passed_options.empty?
        if cloud
          payload['securityGroupLocation']['zoneId'] = cloud['id']
        end

        if cloud['securityServer']
          if cloud['securityServer']['type'] == 'amazon'
            if resource_pool
              payload['securityGroupLocation']['customOptions'] = {'vpc' => resource_pool['externalId']}
            elsif cloud['config'] && cloud['config']['vpc']
              payload['securityGroupLocation']['customOptions'] = {'vpc' => cloud['config']['vpc']}
            end
          elsif cloud['securityServer']['type'] == 'azure'
            if resource_pool
              payload['securityGroupLocation']['customOptions'] = {'resourceGroup' => resource_pool['externalId']}
            elsif cloud['config'] && cloud['config']['resourceGroup']
              payload['securityGroupLocation']['customOptions'] = {'resourceGroup' => cloud['config']['resourceGroup']}
            end
          end
        end
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.create_location(security_group['id'], payload)
        return 0
      end
      json_response = @security_groups_interface.create_location(security_group['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group location #{security_group['name']} - #{cloud['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_location(args)
    cloud_id = nil
    resource_pool_id = nil
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove security group from a location (cloud)." + "\n" +
                    "[security-group] is required. This is the name or id of the security group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      security_group_location = nil
      if security_group['locations']
        security_group_location = security_group['locations'].find {|it| it['zone']['id'] == cloud['id'] }
      end
      if security_group_location.nil?
        print_red_alert "Security group location not found for cloud #{cloud['name']}"
        return 1
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the security group location #{security_group['name']} - #{cloud['name']}?")
        return 9, "aborted command"
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.delete_location(security_group['id'], security_group_location['id'])
        return 0
      end
      json_response = @security_groups_interface.delete_location(security_group['id'], security_group_location['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group location #{security_group['name']} - #{cloud['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def add_rule(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.on( '--name VALUE', String, "Name of the rule" ) do |val|
        options[:options]['name'] = val
      end
      opts.on( '--direction VALUE', String, "Direction" ) do |val|
        options[:options]['direction'] = val
      end
      opts.on( '--rule-type VALUE', String, "Rule Type" ) do |val|
        options[:options]['ruleType'] = val
      end
      opts.on( '--protocol VALUE', String, "Protocol" ) do |val|
        options[:options]['protocol'] = val
      end
      opts.on( '--port-range VALUE', String, "Port Range" ) do |val|
        options[:options]['portRange'] = val
      end
      opts.on( '--source-type VALUE', String, "Source Type" ) do |val|
        options[:options]['sourceType'] = val
      end
      opts.on( '--source VALUE', String, "Source" ) do |val|
        options[:options]['source'] = val
      end
      opts.on( '--source-group VALUE', String, "Source Security Group" ) do |val|
        options[:options]['sourceGroup'] = val
      end
      opts.on( '--source-tier VALUE', String, "Source Tier" ) do |val|
        options[:options]['sourceTier'] = val
      end
      opts.on( '--destination-type VALUE', String, "Destination Type" ) do |val|
        options[:options]['destinationType'] = val
      end
      opts.on( '--destination VALUE', String, "Destination" ) do |val|
        options[:options]['destination'] = val
      end
      opts.on( '--destination-group VALUE', String, "Destination Security Group" ) do |val|
        options[:options]['destinationGroup'] = val
      end
      opts.on( '--destination-tier VALUE', String, "Destination Tier" ) do |val|
        options[:options]['destinationTier'] = val
      end
      opts.footer = "Create a security group rule." + "\n" +
                    "[security-group] is required. This is the name or id of the security group." + "\n"
                    "[name] is required. This is the name of the security group rule."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      # construct payload
      if args[1]
        options[:options]['name'] = args[1]
      end
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'rule' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'rule' => {
          }
        }
        payload.deep_merge!({'rule' => passed_options})  unless passed_options.empty?

        # prompt
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options])
        payload['rule']['name'] = v_prompt['name'] unless v_prompt['name'].nil?

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'direction', 'fieldLabel' => 'Direction', 'type' => 'select', 'optionSource' => 'securityGroupDirection', 'required' => true, 'defaultValue' => 'ingress'}], options[:options], @api_client)
        payload['rule']['direction'] = v_prompt['direction'] unless v_prompt['direction'].nil?

        rule_types = [{"name" => "Custom Rule", "value" => "customRule"}]
        instance_types = @options_interface.options_for_source('instanceTypes',{})
        if instance_types['data']
          instance_types['data'].each do |it|
            rule_types << {"name" => it['name'], "value" => it['code'] || it['value']}
          end
        end
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ruleType', 'fieldLabel' => 'Rule Type', 'type' => 'select', 'selectOptions' => rule_types, 'required' => true, 'defaultValue' => 'customRule'}], options[:options], @api_client)
        payload['rule']['ruleType'] = v_prompt['ruleType'] unless v_prompt['ruleType'].nil?
        
        if payload['rule']['ruleType'] == 'customRule'

          protocols = [{"name" => "TCP", "value" => "tcp"}, {"name" => "UDP", "value" => "udp"}, {"name" => "ICMP", "value" => "icmp"}]
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'protocol', 'fieldLabel' => 'Protocol', 'type' => 'select', 'selectOptions' => protocols, 'required' => true, 'defaultValue' => 'tcp'}], options[:options], @api_client)
          payload['rule']['protocol'] = v_prompt['protocol'] unless v_prompt['protocol'].nil?

          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'portRange', 'fieldLabel' => 'Port Range', 'type' => 'text', 'required' => true}], options[:options])
          payload['rule']['portRange'] = v_prompt['portRange'] unless v_prompt['portRange'].nil?

        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sourceType', 'fieldLabel' => 'Source Type', 'type' => 'select', 'optionSource' => 'securityGroupSourceType', 'required' => true, 'defaultValue' => 'cidr'}], options[:options], @api_client)
        payload['rule']['sourceType'] = v_prompt['sourceType'] unless v_prompt['sourceType'].nil?

        if payload['rule']['sourceType'] == 'cidr'
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'source', 'fieldLabel' => 'Source', 'type' => 'text', 'required' => true, 'description' => 'Source CIDR eg. 0.0.0.0/0'}], options[:options])
          payload['rule']['source'] = v_prompt['source'] unless v_prompt['source'].nil?
        elsif payload['rule']['sourceType'] == 'group'
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sourceGroup', 'fieldLabel' => 'Source Security Group', 'type' => 'select', 'optionSource' => 'securityGroups', 'required' => true}], options[:options], @api_client)
          payload['rule']['sourceGroup'] = {"id" => v_prompt['sourceGroup']} unless v_prompt['sourceGroup'].nil?
        elsif payload['rule']['sourceType'] == 'tier'
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sourceTier', 'fieldLabel' => 'Source Tier', 'type' => 'select', 'optionSource' => 'tiers', 'required' => true}], options[:options], @api_client)
          payload['rule']['sourceTier'] = {"id" => v_prompt['sourceTier']} unless v_prompt['sourceTier'].nil?
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'destinationType', 'fieldLabel' => 'Destination Type', 'type' => 'select', 'optionSource' => 'securityGroupDestinationType', 'required' => true, 'defaultValue' => 'instance'}], options[:options], @api_client)
        payload['rule']['destinationType'] = v_prompt['destinationType'] unless v_prompt['destinationType'].nil?

        if payload['rule']['destinationType'] == 'cidr'
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'destination', 'fieldLabel' => 'Destination', 'type' => 'text', 'required' => true, 'description' => 'Destination CIDR eg. 0.0.0.0/0'}], options[:options])
          payload['rule']['destination'] = v_prompt['destination'] unless v_prompt['destination'].nil?
        elsif payload['rule']['destinationType'] == 'group'
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'destinationGroup', 'fieldLabel' => 'Destination Security Group', 'type' => 'select', 'optionSource' => 'securityGroups', 'required' => true}], options[:options], @api_client)
          payload['rule']['destinationGroup'] = {"id" => v_prompt['destinationGroup']} unless v_prompt['destinationGroup'].nil?
        elsif payload['rule']['destinationType'] == 'tier'
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'destinationTier', 'fieldLabel' => 'Destination Tier', 'type' => 'select', 'optionSource' => 'tiers', 'required' => true}], options[:options], @api_client)
          payload['rule']['destinationTier'] = {"id" => v_prompt['destinationTier']} unless v_prompt['destinationTier'].nil?
        end

      end

      @security_group_rules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_group_rules_interface.dry.create(security_group['id'], payload)
        return 0
      end
      json_response = @security_group_rules_interface.create(security_group['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      display_name = (json_response['rule'] && json_response['rule']['name'].to_s != '') ? json_response['rule']['name'] : json_response['rule']['id']
      print_green_success "Created security group rule #{display_name}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_rule(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a security group rule." + "\n" +
                    "[security-group] is required. This is the name or id of the security group." + "\n"
                    "[rule] is required. This is the name or id of the security group rule."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?
      
      #security_group_rule = find_security_group_rule_by_id(security_group['id'], args[1])
      #return 1 if security_group_rule.nil?

      security_group_rule = nil
      if security_group['rules']
        matching_rules = []
        if args[1].to_s =~ /\A\d{1,}\Z/
          matching_rules = security_group['rules'].select {|it| it['id'].to_s == args[1].to_s }
        else
          matching_rules = security_group['rules'].select {|it| it['name'] == args[1].to_s }
        end
        if matching_rules.size > 1
          print_red_alert "#{matching_rules.size} security group rules found by name '#{args[1]}'"
          rows = matching_rules.collect do |it|
            {id: it['id'], name: it['name']}
          end
          puts as_pretty_table(rows, [:id, :name], {color:red})
          return 1
        else
          security_group_rule = matching_rules[0]
        end
      end
      if security_group_rule.nil?
        print_red_alert "Security group rule not found for '#{args[1]}'"
        return 1
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the security group rule: #{security_group_rule['id']}?")
        return 9, "aborted command"
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_group_rules_interface.dry.delete(security_group['id'], security_group_rule['id'])
        return 0
      end
      json_response = @security_group_rules_interface.delete(security_group['id'], security_group_rule['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      display_name = (security_group_rule['name'].to_s != '') ? security_group_rule['name'] : security_group_rule['id'].to_s
      print_green_success "Deleted security group rule #{display_name}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_rule(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [rule]")
      opts.on( '--name VALUE', String, "Name of the rule" ) do |val|
        options[:options]['name'] = val
      end
      opts.on( '--direction VALUE', String, "Direction" ) do |val|
        options[:options]['direction'] = val
      end
      opts.on( '--rule-type VALUE', String, "Rule Type" ) do |val|
        options[:options]['ruleType'] = val
      end
      opts.on( '--protocol VALUE', String, "Protocol" ) do |val|
        options[:options]['protocol'] = val
      end
      opts.on( '--port-range VALUE', String, "Port Range" ) do |val|
        options[:options]['portRange'] = val
      end
      opts.on( '--source-type VALUE', String, "Source Type" ) do |val|
        options[:options]['sourceType'] = val
      end
      opts.on( '--source VALUE', String, "Source" ) do |val|
        options[:options]['source'] = val
      end
      opts.on( '--source-group VALUE', String, "Source Security Group" ) do |val|
        options[:options]['sourceGroup'] = val
      end
      opts.on( '--source-tier VALUE', String, "Source Tier" ) do |val|
        options[:options]['sourceTier'] = val
      end
      opts.on( '--destination-type VALUE', String, "Destination Type" ) do |val|
        options[:options]['destinationType'] = val
      end
      opts.on( '--destination VALUE', String, "Destination" ) do |val|
        options[:options]['destination'] = val
      end
      opts.on( '--destination-group VALUE', String, "Destination Security Group" ) do |val|
        options[:options]['destinationGroup'] = val
      end
      opts.on( '--destination-tier VALUE', String, "Destination Tier" ) do |val|
        options[:options]['destinationTier'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a security group rule." + "\n" +
                    "[security-group] is required. This is the name or id of the security group." + "\n"
                    "[rule] is required. This is the name or id of the security group rule."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?
      
      #security_group_rule = find_security_group_rule_by_id(security_group['id'], args[1])
      #return 1 if security_group_rule.nil?

      security_group_rule = nil
      if security_group['rules']
        matching_rules = []
        if args[1].to_s =~ /\A\d{1,}\Z/
          matching_rules = security_group['rules'].select {|it| it['id'].to_s == args[1].to_s }
        else
          matching_rules = security_group['rules'].select {|it| it['name'] == args[1].to_s }
        end
        if matching_rules.size > 1
          print_red_alert "#{matching_rules.size} security group rules found by name '#{args[1]}'"
          rows = matching_rules.collect do |it|
            {id: it['id'], name: it['name']}
          end
          puts as_pretty_table(rows, [:id, :name], {color:red})
          return 1
        else
          security_group_rule = matching_rules[0]
        end
      end
      if security_group_rule.nil?
        print_red_alert "Security group rule not found for '#{args[1]}'"
        return 1
      end

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'rule' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'rule' => {
          }
        }
        payload.deep_merge!({'rule' => passed_options})  unless passed_options.empty?

        if passed_options.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_group_rules_interface.dry.update(security_group['id'], security_group_rule['id'], payload)
        return 0
      end
      json_response = @security_group_rules_interface.update(security_group['id'], security_group_rule['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      security_group_rule = json_response['rule']
      display_name = (security_group_rule['name'].to_s != '') ? security_group_rule['name'] : security_group_rule['id'].to_s
      print_green_success "Updated security group rule #{display_name}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # JD: still need this??
  def use(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [--none]")
      opts.on('--none','--none', "Do not use an active group.") do |json|
        options[:unuse] = true
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    if args.length < 1 && !options[:unuse]
      puts optparse
      return
    end
    connect(options)
    begin

      if options[:unuse]
        if @active_security_group[@appliance_name.to_sym] 
          @active_security_group.delete(@appliance_name.to_sym)
        end
        ::Morpheus::Cli::SecurityGroups.save_security_group(@active_security_group)
        unless options[:quiet]
          print cyan
          puts "Switched to no active security group."
          print reset
        end
        print reset
        return # exit 0
      end

      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      if !security_group.nil?
        @active_security_group[@appliance_name.to_sym] = security_group['id']
        ::Morpheus::Cli::SecurityGroups.save_security_group(@active_security_group)
        puts cyan, "Using Security Group #{args[0]}", reset
      else
        puts red, "Security Group not found", reset
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def unuse(args)
    use(args + ['--none'])
  end

  def self.load_security_group_file
    remote_file = security_group_file_path
    if File.exist? remote_file
      return YAML.load_file(remote_file)
    else
      {}
    end
  end

  def self.security_group_file_path
    File.join(Morpheus::Cli.home_directory,"securitygroup")
  end

  def self.save_security_group(new_config)
    fn = security_group_file_path
    if !Dir.exists?(File.dirname(fn))
      FileUtils.mkdir_p(File.dirname(fn))
    end
    File.open(fn, 'w') {|f| f.write new_config.to_yaml } #Store
    FileUtils.chmod(0600, fn)
    new_config
  end

  private

   def find_security_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_security_group_by_id(val)
    else
      return find_security_group_by_name(val)
    end
  end

  def find_security_group_by_id(id)
    begin
      json_response = @security_groups_interface.get(id.to_i)
      return json_response['securityGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Security Group not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_security_group_by_name(name)
    json_response = @security_groups_interface.list({name: name.to_s})
    security_groups = json_response['securityGroups']
    if security_groups.empty?
      print_red_alert "Security Group not found by name #{name}"
      return nil
    elsif security_groups.size > 1
      print_red_alert "#{security_groups.size} security groups found by name #{name}"
      rows = security_groups.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return security_groups[0]
    end
  end

  def find_security_group_rule_by_id(security_group_id, id)
    begin
      json_response = @security_groups_interface.get(security_group_id.to_i, id.to_i)
      return json_response['rule']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Security Group Rule not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

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
      matching_resource_pools = resource_pools.select { |it| name && (it['name'] == name || it['externalId'] == name) }
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
