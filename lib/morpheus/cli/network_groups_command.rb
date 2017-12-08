require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-groups'

  register_subcommands :list, :get, :add, :update, :remove
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_groups_interface = @api_client.network_groups
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
      opts.footer = "List network groups."
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @network_groups_interface.dry.list(params)
        return
      end
      json_response = @network_groups_interface.list(params)
      network_groups = json_response["networkGroups"]
      if options[:include_fields]
        json_response = {"networkGroups" => filter_data(network_groups, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(network_groups, options)
        return 0
      end
      title = "Morpheus Network Groups"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if network_groups.empty?
        print cyan,"No network groups found.",reset,"\n"
      else
        rows = network_groups.collect {|network_group| 
          row = {
            id: network_group['id'],
            name: network_group['name'],
            description: network_group['description'],
            # networks: network_group['networks'] ? network_group['networks'].collect {|it| it['name'] }.uniq.join(', ') : '',
            networks: network_group['networks'] ? network_group['networks'].size : 0,
            visibility: network_group['visibility'].to_s.capitalize,
            tenants: network_group['tenants'] ? network_group['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
          }
          row
        }
        columns = [:id, :name, :description, :networks, :visibility, :tenants]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network group", :n_label => "network groups"})
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
      opts.banner = subcommand_usage("[network-group]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network group." + "\n" +
                    "[network-group] is required. This is the name or id of a network group."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-group]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_groups_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_groups_interface.dry.list({name:args[0]})
        end
        return
      end
      network_group = find_network_group_by_name_or_id(args[0])
      return 1 if network_group.nil?
      json_response = {'networkGroup' => network_group}  # skip redundant request
      # json_response = @network_groups_interface.get(network_group['id'])
      network_group = json_response['networkGroup']
      if options[:include_fields]
        json_response = {'networkGroup' => filter_data(network_group, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([network_group], options)
        return 0
      end
      print_h1 "Network Group Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Networks" => lambda {|it| it['networks'] ? it['networks'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      }
      print_description_list(description_cols, network_group)

      
      if network_group['resourcePermission'].nil?
        print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if network_group['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if network_group['resourcePermission']['sites']
          network_group['resourcePermission']['sites'].each do |site|
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
      
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--networks [id,id,id]")
      opts.on('--name VALUE', String, "Name for this network group") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of network group") do |val|
        options['description'] = val
      end
      opts.on('--networks LIST', Array, "Networks in the group, comma separated list of network IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['networks'] = []
        else
          options['networks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true'
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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network group." + "\n" +
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
        # prompt for network options
        payload = {
          'networkGroup' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['networkGroup'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkGroup']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network group.'}], options)
          payload['networkGroup']['name'] = v_prompt['name']
        end

        # Description
        if options['description']
          payload['networkGroup']['description'] = options['description']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of network group.'}], options)
          payload['networkGroup']['description'] = v_prompt['description']
        end
        
        # Networks
        if options['networks']
          payload['networkGroup']['networks'] = options['networks'].collect {|it| {id: it} }
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networks', 'fieldLabel' => 'Networks', 'type' => 'text', 'required' => true, 'description' => 'Networks in the group, comma separated list of network IDs.'}], options)
          payload['networkGroup']['networks'] = v_prompt['networks'].to_s.split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| {id: it} }
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
          payload['networkGroup']['visibility'] = options['visibility']
        end

      end

      
      if options[:dry_run]
        print_dry_run @network_groups_interface.dry.create(payload)
        return
      end
      json_response = @network_groups_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_group = json_response['networkGroup']
        print_green_success "Added network group #{network_group['name']}"
        get([network_group['id']])
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
      opts.banner = subcommand_usage("[network-group] [options]")
      opts.on('--name VALUE', String, "Name for this network group") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of network group") do |val|
        options['description'] = val
      end
      opts.on('--networks LIST', Array, "Networks in the group, comma separated list of network IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['networks'] = []
        else
          options['networks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true'
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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network group." + "\n" +
                    "[network-group] is required. This is the id of a network group."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      network_group = find_network_group_by_name_or_id(args[0])
      return 1 if network_group.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkGroup' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkGroup'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkGroup']['name'] = options['name']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network group.'}], options)
          # payload['networkGroup']['name'] = v_prompt['name']
        end

        # Description
        if options['description']
          payload['networkGroup']['description'] = options['description']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of network group.'}], options)
          # payload['networkGroup']['description'] = v_prompt['description']
        end
        
        # Networks
        if options['networks']
          payload['networkGroup']['networks'] = options['networks'].collect {|it| {id: it} }
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networks', 'fieldLabel' => 'Networks', 'type' => 'text', 'required' => true, 'description' => 'Networks in the group, comma separated list of network IDs.'}], options)
          # payload['networkGroup']['networks'] = v_prompt['networks'].to_s.split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| {id: it} }
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
          payload['networkGroup']['visibility'] = options['visibility']
        end

      end

      if options[:dry_run]
        print_dry_run @network_groups_interface.dry.update(network_group["id"], payload)
        return
      end
      json_response = @network_groups_interface.update(network_group["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        network_group = json_response['networkGroup']
        print_green_success "Updated network group #{network_group['name']}"
        get([network_group['id']])
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
      opts.banner = subcommand_usage("[network-group]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network group." + "\n" +
                    "[network-group] is required. This is the name or id of a network group."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-group]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      network_group = find_network_group_by_name_or_id(args[0])
      return 1 if network_group.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network group: #{network_group['name']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @network_groups_interface.dry.destroy(network_group['id'])
        return 0
      end
      json_response = @network_groups_interface.destroy(network_group['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network group #{network_group['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


 def find_network_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_group_by_id(val)
    else
      return find_network_group_by_name(val)
    end
  end

  def find_network_group_by_id(id)
    begin
      json_response = @network_groups_interface.get(id.to_i)
      return json_response['networkGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Group not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_group_by_name(name)
    json_response = @network_groups_interface.list({name: name.to_s})
    network_groups = json_response['networkGroups']
    if network_groups.empty?
      print_red_alert "Network Group not found by name #{name}"
      return nil
    elsif network_groups.size > 1
      print_red_alert "#{network_groups.size} network groups found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_groups.collect do |network_group|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return network_groups[0]
    end
  end

end
