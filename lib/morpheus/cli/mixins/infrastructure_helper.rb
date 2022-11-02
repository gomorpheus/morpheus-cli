require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for infrastructure management
module Morpheus::Cli::InfrastructureHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def groups_interface
    # @api_client.groups
    raise "#{self.class} has not defined @groups_interface" if @groups_interface.nil?
    @groups_interface
  end

  def clouds_interface
    # @api_client.clouds
    raise "#{self.class} has not defined @clouds_interface" if @clouds_interface.nil?
    @clouds_interface
  end

  def networks_interface
    # @api_client.networks
    raise "#{self.class} has not defined @networks_interface" if @networks_interface.nil?
    @networks_interface
  end

  def subnets_interface
    # @api_client.subnets
    raise "#{self.class} has not defined @subnets_interface" if @subnets_interface.nil?
    @subnets_interface
  end

  def network_groups_interface
    # @api_client.network_groups
    raise "#{self.class} has not defined @network_groups_interface" if @network_groups_interface.nil?
    @network_groups_interface
  end

  def network_types_interface
    # @api_client.network_types
    raise "#{self.class} has not defined @network_types_interface" if @network_types_interface.nil?
    @network_types_interface
  end
  
  def subnet_types_interface
    # @api_client.subnet_types
    raise "#{self.class} has not defined @subnet_types_interface" if @subnet_types_interface.nil?
    @subnet_types_interface
  end

  def find_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_group_by_id(val)
    else
      return find_group_by_name(val)
    end
  end

  def find_group_by_id(id)
    begin
      json_response = groups_interface.get(id.to_i)
      return json_response['group']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Group not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_group_by_name(name)
    json_results = groups_interface.list({name: name})
    if json_results['groups'].empty?
      print_red_alert "Group not found by name #{name}"
      exit 1
    end
    group = json_results['groups'][0]
    return group
  end

  def find_cloud_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_cloud_by_id(val)
    else
      return find_cloud_by_name(val)
    end
  end

  def find_cloud_by_id(id)
    json_results = clouds_interface.get(id.to_i)
    if json_results['zone'].empty?
      print_red_alert "Cloud not found by id #{id}"
      exit 1
    end
    cloud = json_results['zone']
    return cloud
  end

  def find_cloud_by_name(name)
    json_results = clouds_interface.list({name: name})
    if json_results['zones'].empty?
      print_red_alert "Cloud not found by name #{name}"
      exit 1
    end
    cloud = json_results['zones'][0]
    return cloud
  end

  def get_available_cloud_types(refresh=false, params = {})
    if !@available_cloud_types || refresh
      @available_cloud_types = clouds_interface.cloud_types({max:1000}.deep_merge(params))['zoneTypes']
    end
    return @available_cloud_types
  end

  def cloud_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return cloud_type_for_id(val)
    else
      return cloud_type_for_name(val)
    end
  end
  def cloud_type_for_id(id)
    return get_available_cloud_types().find { |z| z['id'].to_i == id.to_i}
  end

  def cloud_type_for_name(name)
    types = get_available_cloud_types(true, {'name' => name})
    return types.find { |z| z['code'].downcase == name.downcase} || types.find { |z| z['name'].downcase == name.downcase}
  end


  # Networks

  def find_network_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_by_id(val)
    else
      return find_network_by_name(val)
    end
  end

  def find_network_by_id(id)
    begin
      json_response = networks_interface.get(id.to_i)
      return json_response['network']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_by_name(name)
    json_response = networks_interface.list({name: name.to_s})
    networks = json_response['networks']
    if networks.empty?
      print_red_alert "Network not found by name #{name}"
      return nil
    elsif networks.size > 1
      print_red_alert "#{networks.size} networks found by name #{name}"
      rows = networks.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      network = networks[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][network['id']]
        network['tenants'] = json_response['tenants'][network['id']]
      end
      return network
    end
  end

  def find_network_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_type_by_id(val)
    else
      return find_network_type_by_name(val)
    end
  end

  def find_network_type_by_id(id)
    begin
      json_response = network_types_interface.get(id.to_i)
      return json_response['networkType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_type_by_name(name)
    json_response = network_types_interface.list({name: name.to_s})
    network_types = json_response['networkTypes']
    if network_types.empty?
      print_red_alert "Network Type not found by name #{name}"
      return network_types
    elsif network_types.size > 1
      print_red_alert "#{network_types.size} network types found by name #{name}"
      rows = network_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_types[0]
    end
  end

  def find_subnet_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_subnet_by_id(val)
    else
      return find_subnet_by_name(val)
    end
  end

  def find_subnet_by_id(id)
    begin
      json_response = subnets_interface.get(id.to_i)
      return json_response['subnet']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Subnet not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_subnet_by_name(name)
    json_response = subnets_interface.list({name: name.to_s})
    subnets = json_response['subnets']
    if subnets.empty?
      print_red_alert "Subnet not found by name #{name}"
      return nil
    elsif subnets.size > 1
      print_red_alert "#{subnets.size} subnets found by name #{name}"
      rows = subnets.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return subnets[0]
    end
  end

  def find_subnet_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_subnet_type_by_id(val)
    else
      return find_subnet_type_by_name(val)
    end
  end

  def find_subnet_type_by_id(id)
    begin
      json_response = subnet_types_interface.get(id.to_i)
      return json_response['subnetType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Subnet Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_subnet_type_by_name(name)
    json_response = subnet_types_interface.list({name: name.to_s})
    subnet_types = json_response['subnetTypes']
    if subnet_types.empty?
      print_red_alert "Subnet Type not found by name #{name}"
      return subnet_types
    elsif subnet_types.size > 1
      print_red_alert "#{subnet_types.size} subnet types found by name #{name}"
      rows = subnet_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return subnet_types[0]
    end
  end

  def find_network_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_group_by_id(val)
    else
      return find_network_group_by_name(val)
    end
  end

  def find_network_group_by_id(id)
    begin
      json_response = network_groups_interface.get(id.to_i)
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
    json_response = network_groups_interface.list({name: name.to_s})
    network_groups = json_response['networkGroups']
    if network_groups.empty?
      print_red_alert "Network Group not found by name #{name}"
      return nil
    elsif network_groups.size > 1
      print_red_alert "#{network_groups.size} network groups found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_groups.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_groups[0]
    end
  end

  def prompt_for_network(network_id, options={}, required=true, field_name='network', field_label='Network')
    # Prompt for a Network, text input that searches by name or id
    network = nil
    still_prompting = true
    while still_prompting do
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => field_name, 'type' => 'text', 'fieldLabel' => field_label, 'required' => required, 'description' => 'Network name or ID.'}], network_id ? {(field_name) => network_id} : {})
      network_id = v_prompt['network']
      begin
        network = find_network_by_name_or_id(network_id)
      rescue SystemExit => cmdexit
      end
      if options[:no_prompt]
        still_prompting = false
      else
        still_prompting = network ? false : true
      end
      if still_prompting
        network_id = nil
      end
    end
    return {success:!!network, network: network}
  end

  def prompt_for_networks(params, options={}, api_client=nil, api_params={})
    # Networks
    network_list = nil
    network_ids = nil
    still_prompting = true
    if params['networks'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networks', 'type' => 'text', 'fieldLabel' => 'Networks', 'required' => false, 'description' => 'Networks to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['networks'].to_s.empty?
          network_list = v_prompt['networks'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        network_ids = []
        bad_ids = []
        if network_list && network_list.size > 0
          network_list.each do |it|
            found_network = nil
            begin
              found_network = find_network_by_name_or_id(it)
            rescue SystemExit => cmdexit
            end
            if found_network
              network_ids << found_network['id']
            else
              bad_ids << it
            end
          end
        end
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      network_list = params['networks']
      still_prompting = false
      network_ids = []
      bad_ids = []
      if network_list && network_list.size > 0
        network_list.each do |it|
          found_network = nil
          begin
            found_network = find_network_by_name_or_id(it)
          rescue SystemExit => cmdexit
          end
          if found_network
            network_ids << found_network['id']
          else
            bad_ids << it
          end
        end
      end
      if !bad_ids.empty?
        return {success:false, msg:"Networks not found: #{bad_ids}"}
      end
    end
    return {success:true, data: network_ids}
  end

  def prompt_for_subnets(params, options={}, api_client=nil, api_params={})
    # todo: make this a generic method now please.
    # Subnets
    record_list = nil
    record_ids = nil
    still_prompting = true
    if params['subnets'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'subnets', 'type' => 'text', 'fieldLabel' => 'Subnets', 'required' => false, 'description' => 'Subnets to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['subnets'].to_s.empty?
          record_list = v_prompt['subnets'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        record_ids = []
        bad_ids = []
        if record_list && record_list.size > 0
          record_list.each do |it|
            found_record = nil
            begin
              found_record = find_subnet_by_name_or_id(it)
            rescue SystemExit => cmdexit
            end
            if found_record
              record_ids << found_record['id']
            else
              bad_ids << it
            end
          end
        end
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      record_list = params['subnets']
      still_prompting = false
      record_ids = []
      bad_ids = []
      if record_list && record_list.size > 0
        record_list.each do |it|
          found_subnet = nil
          begin
            found_subnet = find_subnet_by_name_or_id(it)
          rescue SystemExit => cmdexit
          end
          if found_subnet
            record_ids << found_subnet['id']
          else
            bad_ids << it
          end
        end
      end
      if !bad_ids.empty?
        return {success:false, msg:"Subnets not found: #{bad_ids}"}
      end
    end
    return {success:true, data: record_ids}
  end

  def network_pool_server_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      "Pools" => lambda {|it| it['pools'] ? anded_list(it['pools'].collect {|p| p['name'] }, 3) : '' },
      # "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def network_pool_server_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      "Username" => lambda {|it| it['serviceUsername'] },
      "Password" => lambda {|it| it['servicePassword'] },
      "Credentials" => lambda {|it| it['credential'] ? (it['credential']['type'] == 'local' ? '(Local)' : it['credential']['name']) : nil },
      "Throttle Rate" => lambda {|it| it['serviceThrottleRate'] },
      "Service Mode" => lambda {|it| it['serviceMode'] },
      # "Disable SSL SNI Verification" => lambda {|it| it['ignoreSsl'] },
      "Ignore SSL" => lambda {|it| format_boolean(it['ignoreSsl']) },
      "Network Filter" => lambda {|it| it['networkFilter'] },
      "Zone Filter" => lambda {|it| it['zoneFilter'] },
      "Tenant Match" => lambda {|it| it['tenantMatch'] },
      "Extra Attributes" => lambda {|it| it['config'] ? it['config']['extraAttributes'] : nil },
      "App ID" => lambda {|it| it['config'] ? it['config']['appId'] : nil },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      #"Pools" => lambda {|it| it['pools'] ? anded_list(it['pools'].collect {|p| p['name'] }, 3) : '' },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def network_pool_server_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

  def network_pool_server_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      # "Integration Code" => 'integrationCode',
      "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Selectable" => lambda {|it| format_boolean(it['selectable']) },
      "Plugin" => lambda {|it| format_boolean(it['isPlugin']) },
      "Embedded" => lambda {|it| format_boolean(it['isEmbedded']) },
    }
  end

end
