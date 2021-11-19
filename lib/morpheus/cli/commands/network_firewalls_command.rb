require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkFirewallsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-firewalls'
  register_subcommands :list_rules, :get_rule, :add_rule, :update_rule, :remove_rule
  register_subcommands :list_rule_groups, :get_rule_group, :add_rule_group, :update_rule_group, :remove_rule_group

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_interface = @api_client.accounts
    @network_servers_interface = @api_client.network_servers
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list_rules(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network firewall rules." + "\n" +
        "[server] is optional. This is the name or id of a network server."
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    _list_rules(server, options)
  end

  def _list_rules(server, options)
    params = parse_list_options(options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.list_firewall_rules(server['id'], params)
      return
    end

    json_response = @network_servers_interface.list_firewall_rules(server['id'], params)
    render_response(json_response, options, 'rules') do
      print_h1 "Network Firewall Rules For: #{server['name']}"
      print cyan

      app_title = server['type']['titleFirewallApplications'].tr(' ', '_').downcase
      rows = json_response['rules'].collect {|it|
        row = {
          id: it['id'], group: it['groupName'], name: it['name'], description: it['description'],
          priority: it['priority'], enabled: format_boolean(it['enabled']), policy: it['policy'], direction: it['direction'],
          source: it['sources'].kind_of?(Array) && it['sources'].count > 0 ? it['sources'].collect {|it| it['name']}.join(', ') : (it['sources'].nil? || it['sources'].empty? ? 'any' : it['source']),
          destination: it['destinations'].count > 0 ? it['destinations'].collect {|it| it['name']}.join(', ') : (it['destinations'].nil? || it['destinations'].empty? ? 'any' : it['destination'])
        }

        if it['applications'].count
          row[app_title] = it['applications'].slice(0, 2).collect {|it| it['name']}.join(', ') + (it['applications'].count > 2 ? '... ' : ' ')
        end
        if it['protocal'] || it['portRange']
          row[app_title] += "#{(it['protocol'] || 'any')} #{it['portRange'] || ''}"
        end
        row[app_title] = 'Any' if it['applications'].count == 0 && row['protocol'].nil? && row['portRange'].nil?

        applied_to = []
        if server['type']['supportsFirewallRuleAppliedTarget']
          applied_to << 'All Edges' if row['config']['applyToAllEdges']
          applied_to << 'Distributed Firewall' if row['config']['applyToAllDistributed']
          applied_to += rule['appliedTargets'].collect {|it| it['name']}
          row[:applied_to] = applied_to.join(', ')
        end
        row
      }

      cols = [:id]

      if server['type']['hasFirewallGroups']
        cols += [:group]
      end

      cols += [:name, :description]
      cols += [:priority] if server['type']['hasSecurityGroupRulePriority']
      cols += [:applied_to] if server['type']['supportsFirewallRuleAppliedTarget']
      cols += [:enabled, :policy, :direction, :source, :destination, app_title.to_sym]
      puts as_pretty_table(rows, cols)
    end
    print reset
  end

  def get_rule(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [rule]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details on a network firewall rule." + "\n" +
        "[server] is optional. This is the name or id of a network server.\n" +
        "[rule] is optional. This is the id of a network firewall rule.\n"
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    rule_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'rule', 'type' => 'select', 'fieldLabel' => 'Firewall Rule', 'selectOptions' => search_rules(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Firewall Rule.'}],options[:options],@api_client,{})['rule']
    _get_rule(server, rule_id, options)
  end

  def _get_rule(server, name_or_id, options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      if name_or_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_servers_interface.dry.get_firewall_rule(server['id'], name_or_id.to_i)
      else
        print_dry_run @network_servers_interface.dry.get_firewall_rule(server['id'], {name: name_or_id})
      end
      return
    end

    if server['type']['hasFirewall']
      rule = find_rule(server['id'], name_or_id)

      return 1 if rule.nil?

      render_response({rule: rule}, options, 'rule') do
        print_h1 "Network Firewall Rule Details"
        print cyan

        description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name']},
          "Description" => lambda {|it| it['description']},
          "Enabled" => lambda {|it| format_boolean(it['enabled'])},
          "Priority" => lambda {|it| it['priority']}
        }

        server['type']['ruleOptionTypes'].reject {|it| it['type'] == 'hidden'}.sort_by {|it| it['displayOrder']}.each do |option_type|
          description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
        end
        print_description_list(description_cols, rule)
      end
    else
      print_red_alert "Firewall not supported for #{server['type']['name']}"
    end
    println reset
  end

  def add_rule(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [group]")
      opts.on( '-g', '--group GROUP', String, "Rule group name or ID" ) do |val|
        options[:group] = val
      end
      opts.on('-n', '--name VALUE', String, "Name for this firewall rule") do |val|
        options[:options]['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description for this firewall rule") do |val|
        options[:options]['description'] = val
      end
      opts.on('--priority VALUE', Integer, "Priority for this firewall rule") do |val|
        options[:options]['priority'] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable") do |val|
        options[:options]['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network firewall rule." + "\n" +
        "[server] is optional. This is the name or id of a network server.\n" +
        "[group] is optional. This is the name of id of rule group (applicable to select network servers)."
    end
    optparse.parse!(args)
    connect(options)

    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    options[:group] = args[1] if options[:group].nil? && args.count == 2

    if !server['type']['hasFirewall']
      print_red_alert "Firewall not supported for #{server['type']['name']}"
      return 1
    end

    if options[:payload]
      payload = options[:payload]
    else
      if server['type']['hasFirewallGroups']
        if !options[:group].nil?
          group = find_rule_group(server['id'], options[:group])
          if group.nil?
            return 1
          end
          group_id = group['id']
        else
          avail_groups = @network_servers_interface.list_firewall_rule_groups(server['id'])['ruleGroups'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
          group_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ruleGroup', 'type' => 'select', 'fieldLabel' => 'Rule Group', 'selectOptions' => avail_groups, 'required' => true, 'description' => 'Select Rule Group.'}],options[:options],@api_client,{})['ruleGroup']
        end
        params['ruleGroup'] = {'id' => group_id}
      end

      params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'Name.'}],options[:options],@api_client,{})['name']
      params['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false, 'description' => 'Description.'}],options[:options],@api_client,{})['description']
      params['enabled'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'description' => 'Enable Router.', 'defaultValue' => true, 'required' => false}], options[:options], @api_client, {})['enabled'] == 'on'

      if server['type']['hasSecurityGroupRulePriority']
        params['priority'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priority', 'type' => 'number', 'fieldLabel' => 'Priority', 'required' => false, 'description' => 'Priority.'}],options[:options],@api_client,{})['priority']
      end

      option_types = server['type']['ruleOptionTypes'].sort_by {|it| it['displayOrder']}

      # prompt options
      option_result = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options].deep_merge({:context_map => {'rule' => ''}}), @api_client, {'networkServerId' => server['id']}, nil, true)
      payload = {'rule' => params.deep_merge(option_result)}
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.create_firewall_rule(server['id'], payload)
      return
    end

    json_response = @network_servers_interface.create_firewall_rule(server['id'], payload)
    render_response(json_response, options, 'rule') do
      print_green_success "\nAdded Network Firewall Rule #{json_response['id']}\n"
      _get_rule(server, json_response['id'], options)
    end
  end

  def update_rule(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [rule]")
      opts.on('-n', '--name VALUE', String, "Name for this firewall rule") do |val|
        params['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description for this firewall rule") do |val|
        params['description'] = val
      end
      opts.on('--priority VALUE', Integer, "Priority for this firewall rule") do |val|
        params['priority'] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network firewall rule.\n" +
        "[server] is optional. This is the name or id of a network server.\n" +
        "[rule] is optional. This is the name or id of an existing rule."
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasFirewall']
      print_red_alert "Firewall not supported for #{server['type']['name']}"
      return 1
    end

    rule_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'rule', 'type' => 'select', 'fieldLabel' => 'Firewall Rule', 'selectOptions' => search_rules(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Firewall Rule.'}],options[:options],@api_client,{})['rule']
    rule = find_rule(server['id'], rule_id)
    return 1 if rule.nil?

    payload = parse_payload(options) || {'rule' => params}
    payload['rule'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && !payload['rule'].nil?

    if payload['rule'].empty?
      option_types = server['type']['ruleOptionTypes'].sort_by {|it| it['displayOrder']}
      print_green_success "Nothing to update"
      println cyan
      edit_option_types = option_types.reject {|it| !it['editable'] || !it['showOnEdit']}

      if edit_option_types.count > 0
        print Morpheus::Cli::OptionTypes.display_option_types_help(
          option_types,
          {:include_context => true, :context_map => {'rule' => ''}, :color => cyan, :title => "Available Firewall Rule Options"}
        )
      end
      exit 1
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.update_firewall_rule(server['id'], rule['id'], payload)
      return
    end

    json_response = @network_servers_interface.update_firewall_rule(server['id'], rule['id'], payload)
    render_response(json_response, options, 'rule') do
      print_green_success "\nUpdated Network Firewall Rule #{rule['id']}\n"
      _get_rule(server, rule['id'], options)
    end
  end

  def remove_rule(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [rule]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network firewall rule.\n" +
        "[server] is optional. This is the name or id of a network server.\n" +
        "[rule] is optional. This is the name of id of an existing rule."
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasFirewall']
      print_red_alert "Firewall not supported for #{server['type']['name']}"
      return 1
    end

    rule_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'rule', 'type' => 'select', 'fieldLabel' => 'Firewall Rule', 'selectOptions' => search_rules(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Firewall Rule.'}],options[:options],@api_client,{})['rule']
    rule = find_rule(server['id'], rule_id)
    return 1 if rule.nil?

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network firewall rule '#{rule['name']}' from server '#{server['name']}'?", options)
      return 9, "aborted command"
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.destroy_firewall_rule(server['id'], rule['id'])
      return
    end
    json_response = @network_servers_interface.destroy_firewall_rule(server['id'], rule['id'])
    render_response(json_response, options, 'rule') do
      print_green_success "\nDeleted Network Firewall Rule #{rule['name']}\n"
      _list_rules(server, options)
    end
  end

  def list_rule_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network firewall rule groups." + "\n" +
        "[server] is required. This is the name or id of a network server."
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?
    _list_rule_groups(server, options)
  end

  def _list_rule_groups(server, options)
    params = parse_list_options(options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.list_firewall_rule_groups(server['id'], params)
      return
    end

    if server['type']['hasFirewallGroups']
      json_response = @network_servers_interface.list_firewall_rule_groups(server['id'], params)
      render_response(json_response, options, 'ruleGroups') do
        print_h1 "#{server['type']['titleFirewallGroups'] || 'Network firewall rule groups'} For: #{server['name']}"
        print cyan
        puts as_pretty_table(json_response['ruleGroups'].collect {|it|
          {id: it['id'], name: it['name'], description: it['description'], priority: it['priority'], category: it['groupLayer']}
        }, [:id, :name, :description, :priority, :category])
      end
    else
      print_red_alert "#{server['type']['titleFirewallGroups'] || 'Network firewall rule groups'} not supported for #{server['type']['name']}"
    end
    print reset
  end

  def get_rule_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [group]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details on a network firewall rule group." + "\n" +
        "[server] is optional. This is the name or id of a network server.\n" +
        "[group] is optional. This is the id of a network firewall rule group.\n"
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    group_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ruleGroup', 'type' => 'select', 'fieldLabel' => 'Firewall Rule Group', 'selectOptions' => search_rule_groups(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Firewall Rule Group.'}],options[:options],@api_client,{})['ruleGroup']
    _get_rule_group(server, group_id, options)
  end

  def _get_rule_group(server, name_or_id, options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      if name_or_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_servers_interface.dry.get_firewall_rule_group(server['id'], name_or_id.to_i)
      else
        print_dry_run @network_servers_interface.dry.list_firewall_rule_groups(server['id'], {name: name_or_id})
      end
      return
    end

    if server['type']['hasFirewallGroups']
      group = find_rule_group(server['id'], name_or_id)
      return 1 if group.nil?

      render_response({ruleGroup: group}, options, 'ruleGroup') do
        print_h1 "Network Firewall Rule Group Details"
        print cyan

        description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name']},
          "Description" => lambda {|it| it['description']},
          "Priority" => lambda {|it| it['priority']},
          "Category" => lambda {|it| it['groupLayer']}
        }

        server['type']['firewallGroupOptionTypes'].reject {|it| it['type'] == 'hidden'}.sort_by {|it| it['displayOrder']}.each do |option_type|
          description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
        end
        print_description_list(description_cols, group)
      end
    else
      print_red_alert "Network firewall rule groups not supported for #{server['type']['name']}"
    end
    println reset
  end

  def add_rule_group(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server]")
      opts.on('-n', '--name VALUE', String, "Name for this firewall rule group") do |val|
        options[:options]['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description for this firewall rule group") do |val|
        options[:options]['description'] = val
      end
      opts.on('--priority VALUE', Integer, "Priority for this firewall rule group") do |val|
        options[:options]['priority'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network firewall rule group." + "\n" +
        "[server] is optional. This is the name or id of a network server.\n";
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasFirewallGroups']
      print_red_alert "Firewall rule groups not supported for #{server['type']['name']}"
      return 1
    end

    if options[:payload]
      payload = options[:payload]
    else
      params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'Name.'}],options[:options],@api_client, {})['name']
      params['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false, 'description' => 'Description.'}],options[:options],@api_client,{})['description']
      params['priority'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priority', 'type' => 'number', 'fieldLabel' => 'Priority', 'required' => false, 'description' => 'Priority.'}],options[:options],@api_client,{})['priority']

      option_types = server['type']['firewallGroupOptionTypes'].sort_by {|it| it['displayOrder']}

      # prompt options
      option_result = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options].deep_merge({:context_map => {'ruleGroup' => ''}}), @api_client, {'networkServerId' => server['id']}, nil, true)
      payload = {'ruleGroup' => params.deep_merge(option_result)}
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.create_firewall_rule_group(server['id'], payload)
      return
    end

    json_response = @network_servers_interface.create_firewall_rule_group(server['id'], payload)
    render_response(json_response, options, 'ruleGroup') do
      print_green_success "\nAdded Network Firewall Rule Group #{json_response['id']}\n"
      _get_rule_group(server, json_response['id'], options)
    end
  end

  def update_rule_group(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [group]")
      opts.on('-n', '--name VALUE', String, "Name for this firewall rule group") do |val|
        options[:options]['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description for this firewall rule group") do |val|
        options[:options]['description'] = val
      end
      opts.on('--priority VALUE', Integer, "Priority for this firewall rule group") do |val|
        options[:options]['priority'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network firewall rule group.\n" +
        "[server] is optional. This is the name or id of an existing network server.\n" +
        "[group] is optional. This is the name or id of an existing network firewall rule group."
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasFirewallGroups']
      print_red_alert "Firewall rule groups not supported for #{server['type']['name']}"
      return 1
    end

    group_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ruleGroup', 'type' => 'select', 'fieldLabel' => 'Firewall Rule Group', 'selectOptions' => search_rule_groups(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Firewall Rule Group.'}],options[:options],@api_client,{})['ruleGroup']
    group = find_rule_group(server['id'], group_id)
    return 1 if group.nil?

    payload = parse_payload(options) || {'ruleGroup' => params}
    payload['ruleGroup'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && !payload['ruleGroup'].nil?

    if payload['ruleGroup'].empty?
      print_green_success "Nothing to update"
      println cyan
      option_types = server['type']['firewallGroupOptionTypes'].sort_by {|it| it['displayOrder']}
      edit_option_types = option_types.reject {|it| !it['editable'] || !it['showOnEdit']}

      if edit_option_types.count > 0
        print Morpheus::Cli::OptionTypes.display_option_types_help(option_types, {:include_context => true, :context_map => {'ruleGroup' => ''}, :color => cyan, :title => "Available Firewall Rule Group Options"})
      end
      exit 1
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.update_firewall_rule_group(server['id'], group['id'], payload)
      return
    end

    json_response = @network_servers_interface.update_firewall_rule_group(server['id'], group['id'], payload)
    render_response(json_response, options, 'ruleGroup') do
      print_green_success "\nUpdated Network Firewall Rule Group #{group['id']}\n"
      _get_rule_group(server, group['id'], options)
    end
  end

  def remove_rule_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [group]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network firewall group.\n" +
        "[server] is optional. This is the name or id of an existing network server.\n" +
        "[group] is optional. This is the name or id of an existing network firewall rule group."
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasFirewallGroups']
      print_red_alert "Firewall rule groups not supported for #{server['type']['name']}"
      return 1
    end

    group_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ruleGroup', 'type' => 'select', 'fieldLabel' => 'Firewall Rule Group', 'selectOptions' => search_rule_groups(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Firewall Rule Group.'}],options[:options],@api_client,{})['ruleGroup']
    group = find_rule_group(server['id'], group_id)
    return 1 if group.nil?

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network firewall rule group '#{group['name']}' from server '#{server['name']}'?", options)
      return 9, "aborted command"
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.destroy_firewall_rule_group(server['id'], group['id'])
      return
    end
    json_response = @network_servers_interface.destroy_firewall_rule_group(server['id'], group['id'])
    render_response(json_response, options, 'ruleGroup') do
      print_green_success "\nDeleted Network Firewall Rule Group #{group['name']}\n"
      _list_rule_groups(server, options)
    end
  end

  private

  def find_network_server(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_server_by_id(val)
    else
      if server = find_network_server_by_name(val)
        return find_network_server_by_id(server['id'])
      end
    end
  end

  def find_network_server_by_id(id)
    begin
      json_response = @network_servers_interface.get(id.to_i)
      return json_response['networkServer']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Server not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_server_by_name(name)
    servers = search_network_servers(name)
    if servers.empty?
      print_red_alert "Network Server not found by name #{name}"
      return nil
    elsif servers.size > 1
      print_red_alert "#{servers.size} network servers found by name #{name}"
      rows = servers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return servers[0]
    end
  end

  def search_network_servers(phrase = nil)
    @network_servers_interface.list(phrase ? {phrase: phrase.to_s} : {})['networkServers']
  end

  def find_rule(server_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_rule_by_id(server_id, val)
    else
      if rule = find_rule_by_name(server_id, val)
        return find_rule_by_id(server_id, rule['id'])
      end
    end
  end

  def find_rule_by_id(server_id, rule_id)
    begin
      json_response = @network_servers_interface.get_firewall_rule(server_id, rule_id.to_i)
      return json_response['rule']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network firewall rule not found by id #{rule_id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_rule_by_name(server_id, name)
    rules = search_rules(server_id, name)
    if rules.empty?
      print_red_alert "Network firewall rule not found by name #{name}"
      return nil
    elsif rules.size > 1
      print_red_alert "#{rules.size} network firewall rules found by name #{name}"
      rows = rules.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return rules[0]
    end
  end

  def search_rules(server_id, phrase = nil)
    @network_servers_interface.list_firewall_rules(server_id, phrase ? {phrase: phrase.to_s} : {})['rules']
  end

  def find_rule_group(server_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_rule_group_by_id(server_id, val)
    else
      if group = find_rule_group_by_name(server_id, val)
        return find_rule_group_by_id(server_id, group['id'])
      end
    end
  end

  def find_rule_group_by_id(server_id, group_id)
    begin
      json_response = @network_servers_interface.get_firewall_rule_group(server_id, group_id.to_i)
      return json_response['ruleGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network firewall rule group not found by id #{group_id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_rule_group_by_name(server_id, name)
    groups = search_rule_groups(server_id, name)
    if groups.empty?
      print_red_alert "Network firewall rule group not found by name #{name}"
      return nil
    elsif groups.size > 1
      print_red_alert "#{groups.size} network firewall rule groups found by name #{name}"
      rows = groups.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return groups[0]
    end
  end

  def search_rule_groups(server_id, phrase = nil)
    @network_servers_interface.list_firewall_rule_groups(server_id, phrase ? {phrase: phrase.to_s} : {})['ruleGroups']
  end

end
