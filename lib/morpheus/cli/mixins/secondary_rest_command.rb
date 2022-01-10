# SecondaryRestCommand is a mixin for Morpheus::Cli command classes.
# for resources that are secondary to some parent resource.
# Provides basic CRUD commands: list, get, add, update, remove
# The parent resource is specified as the first argument for all the comments.
#
# Example of a SecondaryRestCommand for `morpheus load-balancer-virtual-servers`.
#
# class Morpheus::Cli::LoadBalancerVirtualServers
#
#   include Morpheus::Cli::CliCommand
#   include Morpheus::Cli::RestCommand
#   include Morpheus::Cli::SecondaryRestCommand
#   include Morpheus::Cli::LoadBalancersHelper
# 
#   set_command_name :'load-balancer-virtual-servers'
#   register_subcommands :list, :get, :add, :update, :remove
#
#   register_interfaces :load_balancer_virtual_servers,
#                       :load_balancers, :load_balancer_types
#
#   set_rest_parent_name :load_balancers
#
# end
#
module Morpheus::Cli::SecondaryRestCommand
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods

    ## duplicated the rest_* settings with rest_parent_*, for defining the parent resource

    # rest_parent_name is the rest_name for the parent
    def rest_parent_name
      @rest_parent_name || default_rest_parent_name
    end

    def default_rest_parent_name
      words = rest_name.split("_")
      if words.size > 1
        words.pop
        return words.join("_") + "s"
      else
        # this wont happen, default wont make sense in this scenario
        # "parent_" + rest_name
        raise "Unable to determine default_rest_parent_name for rest_name: #{rest_name}, class: #{self}"
      end
    end

    def rest_parent_name=(v)
      @rest_parent_name = v.to_s
    end

    alias :set_rest_parent_name :rest_parent_name=
    alias :set_rest_parent :rest_parent_name=
    #alias :rest_parent= :rest_parent_name=

    # rest_parent_key is the singular name of the resource eg. "neat_thing"
    def rest_parent_key
      @rest_parent_key || default_rest_parent_key
    end

    def default_rest_parent_key
      rest_parent_name.chomp("s")
    end

    def rest_parent_key=(v)
      @rest_parent_key = v.to_s
    end

    alias :set_rest_parent_key :rest_parent_key=

    def rest_parent_arg
      @rest_parent_arg || default_rest_parent_arg
    end

    def default_rest_parent_arg
      rest_parent_key.to_s.gsub("_", " ")
    end

    def rest_parent_arg=(v)
      @rest_parent_arg = v.to_s
    end

    alias :set_rest_parent_arg :rest_parent_arg=

    def rest_parent_param
      @rest_parent_param || default_rest_parent_param
    end

    def default_rest_parent_param
      param = rest_parent_key.to_s.split('_').collect(&:capitalize).join
      "#{param[0].downcase}#{param[1..-1]}Id"
    end

    def rest_parent_param=(v)
      @rest_parent_param = v.to_s
    end

    alias :set_rest_parent_param :rest_parent_param=

    # rest_parent_has_name indicates a resource has a name and can be retrieved by name or id
    # true by default, set to false for lookups by only id
    def rest_parent_has_name
      @rest_parent_has_name != nil ? @rest_parent_has_name :  default_rest_parent_has_name
    end

    def default_rest_parent_has_name
      true
    end

    def rest_parent_has_name=(v)
      @rest_parent_has_name = !!v
    end

    alias :set_rest_parent_has_name :rest_parent_has_name=

    # rest_parent_label is the capitalized resource label eg. "Neat Thing"    
    def rest_parent_label
      @rest_parent_label || default_rest_parent_label
    end

    def default_rest_parent_label
      rest_parent_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end

    def rest_parent_label=(v)
      @rest_parent_label = v.to_s
    end

    alias :set_rest_parent_label :rest_parent_label=

    # the plural version of the label eg. "Neat Things"
    def rest_parent_label_plural
      @rest_parent_label_plural || default_rest_parent_label_plural
    end
    
    def default_rest_parent_label_plural
      #rest_parent_name.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
      rest_parent_label.to_s.pluralize
    end

    def rest_parent_label_plural=(v)
      @rest_parent_label_plural = v.to_s
    end
    
    alias :set_rest_parent_label_plural :rest_parent_label_plural=

    # the name of the default interface, matches the rest name eg. "neat_things"
    def rest_parent_interface_name
      @rest_parent_interface_name || default_rest_parent_interface_name
    end

    def default_rest_parent_interface_name
      rest_parent_name
    end

    def rest_parent_interface_name=(v)
      @rest_parent_interface_name = v.to_s
    end

    alias :set_rest_parent_interface_name :rest_parent_interface_name=

  end

  ## duplicated the rest_* settings with rest_parent, for the parents resource
  
  def rest_parent_name
    self.class.rest_parent_name
  end

  def rest_parent_key
    self.class.rest_parent_key
  end

  def rest_parent_arg
    self.class.rest_parent_arg
  end

  def rest_parent_param
    self.class.rest_parent_param
  end

  def rest_parent_has_name
    self.class.rest_parent_has_name
  end

  def rest_parent_label
    self.class.rest_parent_label
  end

  def rest_parent_label_plural
    self.class.rest_parent_label_plural
  end

  def rest_parent_interface_name
    self.class.rest_parent_interface_name # || "@#{rest_parent_name}_interface"
  end

  def rest_parent_interface
    instance_variable_get("@#{rest_parent_interface_name}_interface")
  end

  def rest_parent_object_key
    send("#{rest_parent_key}_object_key")
  end

  def rest_parent_list_key
    send("#{rest_parent_key}_list_key")
  end

  def rest_parent_column_definitions(options)
    send("#{rest_parent_key}_column_definitions", options)
  end

  def rest_parent_list_column_definitions(options)
    send("#{rest_parent_key}_list_column_definitions", options)
  end

  def rest_parent_find_by_name_or_id(val)
    # use explicitly defined finders
    # else default to new generic CliCommand find_by methods
    if rest_parent_has_name
      if respond_to?("find_#{rest_parent_key}_by_name_or_id", true)
        send("find_#{rest_parent_key}_by_name_or_id", val)
      else
        find_by_name_or_id(rest_parent_key, val)
      end
    else
      if respond_to?("find_#{rest_parent_key}_by_id", true)
        send("find_#{rest_parent_key}_by_id", val)
      else
        find_by_id(rest_parent_key, val)
      end
    end
  end

  # override RestCommand method to include parent_id parameter
  def rest_find_by_name_or_id(parent_id, val)
    # use explicitly defined finders
    # else default to new generic CliCommand find_by methods
    if rest_has_name
      if respond_to?("find_#{rest_key}_by_name_or_id", true)
        send("find_#{rest_key}_by_name_or_id", parent_id, val)
      else
        find_by_name_or_id(rest_key, parent_id, val)
      end
    else
      if respond_to?("find_#{rest_key}_by_id", true)
        send("find_#{rest_key}_by_id", parent_id, val)
      else
        find_by_id(rest_key, parent_id, val)
      end
    end
  end

  def registered_interfaces
    self.class.registered_interfaces
  end

  def list(args)
    parent_id, parent_record = nil, nil
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [search]")
      build_list_options(opts, options, params)
      opts.footer = <<-EOT
List #{rest_label_plural.downcase}.
[#{rest_parent_arg}] is required. This is the #{rest_parent_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[search] is optional. This is a search phrase to filter the results.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    parent_id = args[0]
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      return 1, "#{rest_parent_label} not found for '#{parent_id}"
    end
    parent_id = parent_record['id']
    parse_list_options!(args.count > 1 ? args[1..-1] : [], options, params)
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.list(parent_id, params)
      return
    end
    json_response = rest_interface.list(parent_id, params)
    render_response(json_response, options, rest_list_key) do
      records = json_response[rest_list_key]
      print_h1 "Morpheus #{rest_label_plural}"
      if records.nil? || records.empty?
        print cyan,"No #{rest_label_plural.downcase} found.",reset,"\n"
      else
        print as_pretty_table(records, rest_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response) if json_response['meta']
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}]")
      build_get_options(opts, options, params)
      opts.footer = <<-EOT
Get details about #{a_or_an(rest_label)} #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the #{rest_parent_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    parse_get_options!(args.count > 1 ? args[1..-1] : [], options, params)
    parent_id = args[0]
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      return 1, "#{rest_parent_label} not found for '#{parent_id}"
    end
    parent_id = parent_record['id']
    id = args[1..-1].join(" ")
    _get(parent_id, id, params, options)
  end

  def _get(parent_id, id, params, options)
    if id !~ /\A\d{1,}\Z/
      record = rest_find_by_name_or_id(parent_id, id)
      if record.nil?
        return 1, "#{rest_label} not found for '#{id}"
      end
      id = record['id']
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.get(parent_id, id, params)
      return
    end
    json_response = rest_interface.get(parent_id, id, params)
    render_response_for_get(json_response, options)
    return 0, nil
  end

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      # show config settings...
      if record['optionTypes'] && record['optionTypes'].size > 0
        print_h2 "Option Types", options
        print format_option_types_table(record['optionTypes'], options, rest_object_key)
      end
      print reset,"\n"
    end
  end

  def add(args)
    parent_id, parent_record = nil, nil
    record_type_id = nil
    options = {}
    option_types = respond_to?("add_#{rest_key}_option_types", true) ? send("add_#{rest_key}_option_types") : []
    advanced_option_types = respond_to?("add_#{rest_key}_advanced_option_types", true) ? send("add_#{rest_key}_advanced_option_types") : []
    type_option_type = option_types.find {|it| it['fieldName'] == 'type'} 
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}]")
      if rest_has_type && type_option_type.nil?
        opts.on( '-t', "--#{rest_type_arg} TYPE", "#{rest_type_label}" ) do |val|
          record_type_id = val
        end
      end
      build_option_type_options(opts, options, option_types)
      build_option_type_options(opts, options, advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the #{rest_parent_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the name of the new #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max: 2)
    # todo: make supporting args[0] optional and more flexible
    # for now args[0] is assumed to be the 'name'
    record_name = nil
    parent_id = args[0]
    if rest_has_name
      if args[1]
        record_name = args[1]
      end
      verify_args!(args:args, optparse:optparse, min:1, max: 2)
    else
      verify_args!(args:args, optparse:optparse, count: 1)
    end
    connect(options)
    # load parent record
    # todo: prompt instead of error
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      return 1, "#{rest_parent_label} not found for '#{parent_id}"
    end
    parent_id = parent_record['id']
    # load or prompt for type
    if rest_has_type && type_option_type.nil?
      if record_type_id.nil?
        #raise_command_error "#{rest_type_label} is required.\n#{optparse}"
        type_list = rest_type_interface.list({max:10000, creatable: true})[rest_type_list_key]
        type_dropdown_options = type_list.collect {|it| {'name' => it['name'], 'value' => it['code']} }
        record_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => rest_type_label, 'type' => 'select', 'selectOptions' => type_dropdown_options, 'required' => true}], options[:options], @api_client)['type']
      end
      record_type = rest_type_find_by_name_or_id(record_type_id)
      if record_type.nil?
        return 1, "#{rest_type_label} not found for '#{record_type_id}"
      end
    end
    passed_options = parse_passed_options(options)
    options[:params] ||= {}
    options[:params][rest_parent_param] = parent_id
    options[:options]['_object_key'] = rest_object_key
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options})
    else
      record_payload = {}
      if record_name
        record_payload['name'] = record_name
        options[:options]['name'] = record_name # injected for prompt
        options[:options][rest_arg] = record_name
      end
      if rest_has_type && record_type
        # record_payload['type'] = {'code' => record_type['code']}
        record_payload['type'] = record_type['code']
        options[:options]['type'] = record_type['code'] # injected for prompt
        # initialize params for loading optionSource data
        options[:params]['type'] = record_type['code']
      end
      record_payload.deep_merge!(passed_options)
      if option_types && !option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # options by type
      if rest_has_type && record_type.nil?
        type_value = record_payload['type'].is_a?(Hash) ? record_payload['type']['id'] : record_payload['type']
        if type_value
          record_type = rest_type_find_by_name_or_id(type_value)
          if record_type.nil?
            return 1, "#{rest_type_label} not found for '#{type_value}"
          end
        end
        # reload the type by id to get all the details ie. optionTypes
        if record_type && record_type['optionTypes'].nil?
          record_type = rest_type_find_by_name_or_id(record_type['id'])
        end
      end
      if respond_to?("load_option_types_for_#{rest_key}", true)
        my_option_types = send("load_option_types_for_#{rest_key}", record_type, parent_record)
      else
        my_option_types = record_type ? record_type['optionTypes'] : nil
      end
      if my_option_types && !my_option_types.empty?
        # remove redundant fieldContext
        my_option_types.each do |option_type| 
          if option_type['fieldContext'] == rest_object_key
            option_type['fieldContext'] = nil
          end
        end
        api_params = (options[:params] || {}).merge(record_payload)
        v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, api_params)
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # advanced options (uses no_prompt)
      if advanced_option_types && !advanced_option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(advanced_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.create(parent_id, payload)
      return
    end
    json_response = rest_interface.create(parent_id, payload)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_green_success "Added #{rest_label.downcase} #{record['name'] || record['id']}"
      return _get(parent_id, record["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    parent_id = args[0]
    id = args[1]
    record_type = nil
    record_type_id = nil
    options = {}
    option_types = respond_to?("update_#{rest_key}_option_types", true) ? send("update_#{rest_key}_option_types") : []
    advanced_option_types = respond_to?("update_#{rest_key}_advanced_option_types", true) ? send("update_#{rest_key}_advanced_option_types") : []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}] [options]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the #{rest_parent_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      return 1, "#{rest_parent_label} not found for '#{parent_id}"
    end
    parent_id = parent_record['id']
    connect(options)
    record = rest_find_by_name_or_id(parent_id, id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    # load type so we can prompt for those option types
    if rest_has_type
      record_type_id = record['type']['id']
      record_type = rest_type_find_by_name_or_id(record_type_id)
      if record_type.nil?
        return 1, "#{rest_type_label} not found for '#{record_type_id}"
      end
      # reload the type by id to get all the details ie. optionTypes
      if record_type['optionTypes'].nil?
        record_type = rest_type_find_by_name_or_id(record_type['id'])
      end
    end
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options}) unless passed_options.empty?
    else
      record_payload = passed_options
      if rest_has_type && record_type
        # inject type to options for prompting
        # record_payload['type'] = record_type['code']
        # options[:options]['type'] = record_type['code']
        # initialize params for loading optionSource data
        options[:params] ||= {}
        options[:params]['type'] = record_type['code']
      end
      # update options without prompting by default
      if false && option_types && !option_types.empty?
        api_params = (options[:params] || {}).merge(record_payload) # need to merge in values from record too, ughhh
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(option_types, options[:options], @api_client, api_params)
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # options by type
      my_option_types = nil
      if respond_to?("load_option_types_for_#{rest_key}", true)
        my_option_types = send("load_option_types_for_#{rest_key}", record_type, parent_record)
      else
        my_option_types = record_type ? record_type['optionTypes'] : nil
      end
      if false && my_option_types && !my_option_types.empty?
        # remove redundant fieldContext
        # make them optional for updates
        # todo: use current value as default instead of just making things optioanl
        # maybe new prompt() options like {:mode => :edit, :object => storage_server} or something
        my_option_types.each do |option_type| 
          if option_type['fieldContext'] == rest_object_key
            option_type['fieldContext'] = nil
          end
          option_type.delete('required')
          option_type.delete('defaultValue')
        end
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(my_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # advanced options
      if false && advanced_option_types && !advanced_option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(advanced_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # remove empty config, compact could hanlde this
      if record_payload['config'] && record_payload['config'].empty?
        record_payload.delete('config')
      end
      # prevent updating with empty payload
      if record_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.update(parent_id, record['id'], payload)
      return
    end
    json_response = rest_interface.update(parent_id, record['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "Updated #{rest_label.downcase} #{record['name'] || record['id']}"
      _get(parent_id, record["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    parent_id = args[0]
    id = args[1]
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an existing #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the #{rest_parent_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      return 1, "#{rest_parent_label} not found for '#{parent_id}"
    end
    record = rest_find_by_name_or_id(parent_record['id'], id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the #{rest_label.downcase} #{record['name'] || record['id']}?")
      return 9, "aborted"
    end
    params.merge!(parse_query_options(options))
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.destroy(parent_id, record['id'], params)
      return 0, nil
    end
    json_response = rest_interface.destroy(parent_id, record['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed #{rest_label.downcase} #{record['name'] || record['id']}"
    end
    return 0, nil
  end

end

