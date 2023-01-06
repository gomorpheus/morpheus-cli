require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkServerGroups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::WhoamiHelper
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::ProvisioningHelper

  set_command_description "View and manage network server groups."
  set_command_name :'network-server-groups'
  register_subcommands :list, :get, :add, :update, :remove
  register_interfaces :network_servers, :network_server_groups, :accounts
  set_rest_perms_config({enabled:true, excludes:['groups', 'plans', 'visibility', 'resource'], context: 'permissions'})

  protected

  NSXT_CRITERIA_TYPES = ['Condition', 'NestedExpression']
  NSXT_MEMBER_TYPES = ['Path', 'ExternalID']
  NSXT_IP_TYPES = ['IPAddress', 'MACAddress']
  NSXT_AD_GROUP_TYPES = ['IdentityGroup']

  def network_server_group_list_key
    'groups'
  end

  def network_server_group_object_key
    'group'
  end

  def network_server_group_field_context
    network_server_group_object_key
  end

  def load_option_types_for_network_server_group(record_type, parent_record)
    parent_record['type']['groupOptionTypes']
  end

  def network_server_group_list_column_definitions(options)
    if options[:parent_record]['type']['code'] == 'nsx-t'
      members_lambda = lambda do |group|
        members = []
        {
          'Criteria' => NSXT_CRITERIA_TYPES,
          'Members' => NSXT_MEMBER_TYPES,
          'IPS / MACS' => NSXT_IP_TYPES,
          'AD Groups' => NSXT_AD_GROUP_TYPES
        }.each do |label, types|
          if (count = group['members'].select{|member| types.include?(member['type'])}.count) > 0
            members << "#{count} #{label}"
          end
        end
        members.join(', ')
      end
    else
      members_lambda = lambda do |group|
        group['members'].collect{|member| member['type']}.join(', ')
      end
    end

    columns = {
      'ID' => 'id',
      'Name' => 'name',
      'Description' => 'description',
      'Members' => members_lambda
    }

    if is_master_account
      columns['Visibility'] = lambda {|it| it['visibility'].capitalize}
      columns['Tenants'] = lambda do |it|
        tenants = []
        if it['permissions'] and it['permissions']['tenantPermissions']
          tenants = @accounts_interface.list({:ids => it['permissions']['tenantPermissions']['accounts']})['accounts'].collect{|account| account['name']}
        end
        tenants.join(', ')
      end
    end
    columns
  end

  def network_server_group_column_definitions(options)
    if options[:parent_record]['type']['code'] == 'nsx-t'
      tags_lambda = lambda{|group|
        (group['tags'] || []).collect{|tag|
          "#{tag['name']}#{(tag['value'] || '').length > 0 ? " (scope: #{tag['value']})" : ''}"
        }.join(', ')
      }
    else
      tags_lambda = lambda {|group| group['tags'] ? format_metadata(group['tags']) : '' }
    end
    columns = {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Tags" => tags_lambda
    }
    columns
  end

  def network_server_group_add_prompt(record_payload, record_type, parent_record, options)
    unless parent_record['type']['code'] != 'nsx-t' or options[:no_prompt]
      nsxt_add_prompt(record_payload, record_type, parent_record, options)
    end
  end

  def nsxt_add_prompt(record_payload, record_type, parent_record, options)
    # criteria
    criteria = []
    while criteria.count < 5 && Morpheus::Cli::OptionTypes.confirm("Add#{criteria.count == 0 ? '': ' another'} criteria?", {:default => false})
      if true #members.count == 0 or members.last['memberValue'] == 'OR' # Can't have nested follow AND conjunction
        type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Criteria Type', 'type' => 'select', 'selectOptions' => ['Condition', 'Nested Expression'].map{|it| {'name' => it, 'value' => it.sub(' ', '')}}, 'required' => true, 'defaultValue' => 'Condition'}], options[:options])['type']
      end
      prompt_condition = lambda do
        compare_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memberType', 'fieldLabel' => 'Criteria Item', 'type' => 'select', 'selectOptions' => ['Virtual Machine', 'Segment Port', 'Segment', 'IP Set'].map{|it| {'name' => it, 'value' => it.sub(' ', '')}}, 'required' => true, 'defaultValue' => 'VirtualMachine'}], options[:options])['memberType']
        compare_key = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'key', 'fieldLabel' => "#{compare_type} Field", 'type' => 'select', 'selectOptions' => (compare_type == 'VirtualMachine' ? ['Name', 'Tag', 'OS Name', 'Computer Name'] : ['Tag'] ).map{|it| {'name' => it, 'value' => it.sub(' ', '')}}, 'required' => true, 'defaultValue' => 'Tag'}], options[:options])['key']
        compare_operator = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'operator', 'fieldLabel' => "#{compare_key} Operator", 'type' => 'select', 'selectOptions' => (compare_type == 'VirtualMachine' ? ['Equals', 'Contains', 'Starts With', 'Ends With'] : ['Equals']).map{|it| {'name' => it, 'value' => it.sub(' ', '').upcase}}, 'required' => true, 'defaultValue' => 'EQUALS'}], options[:options])['operator']
        compare_value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'value', 'type' => 'text', 'fieldLabel' => "#{compare_key} Value", 'required' => true, 'description' => 'Value to compare.'}], options[:options])['value']
        compare_scope = nil
        if compare_key == 'Tag'
          compare_scope = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scope', 'type' => 'text', 'fieldLabel' => "#{compare_key} Scope", 'required' => false}], options[:options], @api_client, {}, false, true)['scope']
        end
        compare_expr = {key: compare_key, operator: compare_operator, value: compare_value}
        compare_expr.merge!({scope: compare_scope}) if compare_scope
        {'type' => 'Condition', 'memberType' => compare_type, 'memberExpression' => JSON.generate(compare_expr)}
      end

      if criteria.count > 0
        criteria.last['memberValue'] = 'OR'
      end

      if type == 'Condition'
        prev_criteria = criteria.count > 0 ? criteria.last : nil
        criteria << prompt_condition.call
        if prev_criteria and prev_criteria['type'] != 'NestedExpression' and prev_criteria['memberType'] == criteria.last['memberType']
          prev_criteria['memberValue'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memberValue', 'fieldLabel' => 'And/Or', 'type' => 'select', 'selectOptions' => ['and', 'or'].map{|it| {'name' => it, 'value' => it.upcase}}, 'required' => true, 'defaultValue' => 'AND', 'description' => 'Conjunction to use between this condition and the previous condition'}], options[:options])['memberValue']
        end
      else
        # just prompt for conditions w/
        nested_members = [prompt_condition.call]
        while nested_members.count < 5 && Morpheus::Cli::OptionTypes.confirm("Add another criteria to nested expression?", {:default => false})
          nested_members.last['memberValue'] = 'AND'
          nested_members << prompt_condition.call
        end
        criteria << {'type' => type, 'members' => nested_members}
      end
    end

    members = []
    while members.count < 500 && Morpheus::Cli::OptionTypes.confirm("Add#{members.count == 0 ? '': ' another'} member?", {:default => false})
      member_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memberType', 'fieldLabel' => 'Member Type', 'type' => 'select', 'selectOptions' => ['Group', 'Segment', 'Segment Port', 'Virtual Network Interface', 'Virtual Machine', 'Physical Server'].map{|it| {'name' => it, 'value' => it.gsub(' ', '')}}, 'required' => true, 'defaultValue' => 'Group'}], options[:options])['memberType']
      member_value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memberValue', 'fieldLabel' => member_type, 'type' => 'select', 'optionSource' => 'nsxtGroupMembers', 'optionSourceType' => 'nsxt', 'required' => true}], options[:options], @api_client, {networkServerId: parent_record['id'], memberType: member_type}, false, true)['memberValue']
      type = ['Group', 'Segment', 'SegmentPort'].include?(member_type) ? 'Path' : 'ExternalID'
      members << {'type' => type, 'memberType' => member_type, 'memberValue' => member_value}
    end

    # ip/mac
    ips = []
    while members.count + ips.count < 500 && Morpheus::Cli::OptionTypes.confirm("Add#{ips.count == 0 ? '': ' another'} IP/MAC address?", {:default => false})
      member_value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ipAddress', 'type' => 'text', 'fieldLabel' => "IP/MAC Address", 'required' => true, 'description' => 'Enter an IP or MAC address. x.x.x.x'}], options[:options])['ipAddress']
      type = member_value.match(/[a-fA-F0-9]{2}(:[a-fA-F0-9]{2}){5}/) ? 'MACAddress' : 'IPAddress'
      ips << {'type' => type, 'memberValue' => member_value}
    end

    # ad groups
    ad_groups = []
    while members.count + ips.count + ad_groups.count < 500 && Morpheus::Cli::OptionTypes.confirm("Add#{ad_groups.count == 0 ? '': ' another'} AD Group?", {:default => false})
      member_value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'identityGroup', 'type' => 'select', 'optionSource' => 'nsxtIdentityGroups', 'optionSourceType' => 'nsxt', 'required' => true, 'fieldLabel' => "AD Group"}], options[:options], @api_client, {networkServerId: parent_record['id'], memberType: member_type}, false, true)['identityGroup']
      ad_groups << {'type' => 'IdentityGroup', 'memberValue' => member_value}
    end

    record_payload['members'] = criteria + members + ips + ad_groups
    record_payload
  end

  def render_response_details_for_get(record, options)
    if options[:parent_record]['type']['code'] == 'nsx-t'
      members = record['members'].select{|member| NSXT_CRITERIA_TYPES.include?(member['type'])}
      if members.count > 0
        cond_criteria = lambda do |member|
          expr = JSON.parse(member['memberExpression'])
          "#{member['memberType']} #{expr['key']} #{expr['operator']} #{expr['value']}#{expr['scope'].nil? ? '' : " w/ #{expr['scope']} scope"}"
        end
        criteria_parts = []
        members.each_with_index do |member, index|
          if member['type'] == 'NestedExpression'
            criteria_parts << "("
            member['members'].each do |child_member|
              criteria_parts << "  #{cond_criteria.call(child_member)}"
              criteria_parts << "  #{child_member['memberValue']}"
            end
            criteria_parts.pop # remove last conjunction
            criteria_parts << ")"
          else
            criteria_parts << cond_criteria.call(member)
            criteria_parts << member['memberValue']
          end
        end
        criteria_parts.pop if ['AND', 'OR'].include?(criteria_parts.last) # remove last conjunction
        print_h2 "Criteria (#{members.count})", options
        print "#{cyan}#{criteria_parts.join("\n")}\n"
      end

      members = record['members'].select{|member| NSXT_MEMBER_TYPES.include?(member['type'])}
      if members.count > 0
        print_h2 "Members (#{members.count})", options
        print as_pretty_table(members, {'Type' => 'memberType', 'Path/ExternalID' => 'memberValue'}, options)
      end

      members = record['members'].select{|member| NSXT_IP_TYPES.include?(member['type'])}
      if members.count > 0
        print_h2 "IP/MAC Addresses (#{members.count})", options
        print "#{cyan}#{members.collect{|member| "#{member['memberValue']}"}.join("\n")}\n"
      end

      members = record['members'].select{|member| NSXT_AD_GROUP_TYPES.include?(member['type'])}
      if members.count > 0
        print_h2 "AD Groups (#{members.count})", options
        print "#{cyan}#{members.collect{|member| "#{member['memberValue']}"}.join("\n")}\n"
      end
    end
  end
end