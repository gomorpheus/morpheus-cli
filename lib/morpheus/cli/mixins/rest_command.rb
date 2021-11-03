# RestCommand is a mixin for Morpheus::Cli command classes.
# Provides basic CRUD commands: list, get, add, update, remove
# Currently the command class must also include Morpheus::Cli::CliCommand
# The command class can define a few variables to dictate what the resource
# is called and the the api interface used to fetch the records. The command class 
# or helper must also provide several methods to provide the default behavior.
# In the example below, the command (helper) defines the following methods:
#  * load_balancer_object_key() - Key name of object returned by the "get" api endpoint.
#  * load_balancer_list_key() - Key name of array of records returned by the "list" api endpoint.
#  * load_balancer_column_definitions() - Column definitions for the "get" command display output.
#  * load_balancer_list_column_definitions() - Column definitions for the "list" command display output.
#
# Example of a RestCommand for `morpheus load-balancers`.
#
# class Morpheus::Cli::LoadBalancers
#
#   include Morpheus::Cli::CliCommand
#   include Morpheus::Cli::RestCommand
#   include Morpheus::Cli::LoadBalancersHelper
#
#   # All of the example settings below are redundant
#   # and would be the default values if not set.
#   set_rest_name :load_balancers
#   set_rest_label "Load Balancer"
#   set_rest_label_plural "Load Balancers"
#   set_rest_object_key "load_balancer"
#   set_rest_has_type true
#   set_rest_type "load_balancer_types"
#   register_interfaces :load_balancers, :load_balancer_types
#
# end
#
module Morpheus::Cli::RestCommand
  def self.included(base)
    #puts "including RestCommand for #{base}"
    #base.send :include, Morpheus::Cli::CliCommand
    base.extend ClassMethods
  end

  module ClassMethods

    # rest_name is the plural name of the rest command resource eg. NeatThingsCommand would be "neat_things"
    # It is used to derive all other default rest settings key, label, etc.  
    # The default name the command name with underscores `_` instead of dashes `-`.
    def rest_name
      @rest_name || default_rest_name
    end

    def default_rest_name
      self.command_name.to_s.gsub("-", "_")
    end

    def rest_name=(v)
      @rest_name = v.to_s
    end

    alias :set_rest_name :rest_name=

    # rest_key is the singular name of the resource eg. "neat_thing"
    def rest_key
      @rest_key || default_rest_key
    end

    def default_rest_key
      rest_name.to_s.chomp("s")
    end

    def rest_key=(v)
      @rest_key = v.to_s
    end

    alias :set_rest_key :rest_key=

    # rest_arg is a label for the arg in the command usage eg. "thing" gets displayed as [thing]
    def rest_arg
      @rest_arg || default_rest_arg
    end

    def default_rest_arg
      rest_key.gsub("_", " ") # "[" + rest_key.gsub("_", " ") + "]"
    end

    def rest_arg=(v)
      @rest_arg = v.to_s
    end

    alias :set_rest_arg :rest_arg=

    # rest_label is the capitalized resource label eg. "Neat Thing"    
    def rest_label
      @rest_label || default_rest_label
    end

    def default_rest_label
      rest_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end

    def rest_label=(v)
      @rest_label = v.to_s
    end

    alias :set_rest_label :rest_label=

    # the plural version of the label eg. "Neat Things"
    def rest_label_plural
      @rest_label_plural || default_rest_label_plural
    end
    
    def default_rest_label_plural
      #rest_name.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
      rest_label.to_s.pluralize
    end

    def rest_label_plural=(v)
      @rest_label_plural = v.to_s
    end
    
    alias :set_rest_label_plural :rest_label_plural=

    # rest_interface_name is the interface name for the resource. eg. "neat_things"
    def rest_interface_name
      @rest_interface_name || default_rest_interface_name
    end

    def default_rest_interface_name
      rest_name
    end

    def rest_interface_name=(v)
      @rest_interface_name = v.to_s
    end

    alias :set_rest_interface_name :rest_interface_name=

    # rest_has_type indicates a resource has a type. default is false
    def rest_has_type
      @rest_has_type == true
    end

    def default_rest_has_type
      false
    end

    def rest_has_type=(v)
      @rest_has_type = !!v
    end

    alias :set_rest_has_type :rest_has_type=

    ## duplicated the rest_* settings with rest_type, for the types resource

    # rest_type_name is the rest_name for the type, only applicable if rest_has_type
    def rest_type_name
      @rest_type_name || default_rest_type_name
    end

    def default_rest_type_name
      rest_key + "_types"
    end

    def rest_type_name=(v)
      @rest_type_name = v.to_s
    end

    alias :set_rest_type_name :rest_type_name=
    alias :set_rest_type :rest_type_name=
    #alias :rest_type= :rest_type_name=

    # rest_type_key is the singular name of the resource eg. "neat_thing"
    def rest_type_key
      @rest_type_key || default_rest_type_key
    end

    def default_rest_type_key
      rest_type_name.chomp("s")
    end

    def rest_type_key=(v)
      @rest_type_key = v.to_s
    end

    alias :set_rest_type_key :rest_type_key=

    def rest_type_arg
      @rest_type_arg || default_rest_type_arg
    end

    def default_rest_type_arg
      # rest_type_key.gsub("_", " ") # "[" + rest_key.gsub("_", " ") + "]"
      "type" # [type]
    end

    def rest_type_arg=(v)
      @rest_type_arg = v.to_s
    end

    alias :set_rest_type_arg :rest_type_arg=

    # rest_type_label is the capitalized resource label eg. "Neat Thing"    
    def rest_type_label
      @rest_type_label || default_rest_type_label
    end

    def default_rest_type_label
      rest_type_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end

    def rest_type_label=(v)
      @rest_type_label = v.to_s
    end

    alias :set_rest_type_label :rest_type_label=

    # the plural version of the label eg. "Neat Things"
    def rest_type_label_plural
      @rest_type_label_plural || default_rest_type_label_plural
    end
    
    def default_rest_type_label_plural
      #rest_type_name.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
      rest_type_label.to_s.pluralize
    end

    def rest_type_label_plural=(v)
      @rest_type_label_plural = v.to_s
    end
    
    alias :set_rest_type_label_plural :rest_type_label_plural=

    # the name of the default interface, matches the rest name eg. "neat_things"
    def rest_type_interface_name
      @rest_type_interface_name || default_rest_type_interface_name
    end

    def default_rest_type_interface_name
      rest_type_name
    end

    def rest_type_interface_name=(v)
      @rest_type_interface_name = v.to_s
    end

    alias :set_rest_type_interface_name :rest_type_interface_name=

    # set or append to the list of interface names to register for this command
    # The registered interfaces will be pre-loaded into instance variables
    # eg. [:neat_things, :neat_thing_types] will instantiate @neat_things_interface and @neat_thing_types_interface
    def register_interfaces(*interfaces)
      @registered_interfaces ||= []
      interfaces.flatten.each do |it|
        @registered_interfaces << it.to_s
      end
      # put the default rest_interface first
      if rest_interface_name && !@registered_interfaces.include?(rest_interface_name)
        @registered_interfaces.unshift(rest_interface_name)
      end
      # and also the rest_type_interface
      if rest_has_type && !@registered_interfaces.include?(rest_type_interface_name)
        @registered_interfaces.unshift(rest_type_interface_name)
      end
    end

    alias :register_interface :register_interfaces

    # get list of interface names that are registered for this command
    # automatically includes the interface for the rest_name and rest_type_name if has_type
    def registered_interfaces
      @registered_interfaces ||= []
      # put the default rest_interface first
      if @registered_interfaces.empty?
        if rest_interface_name
          @registered_interfaces.unshift(rest_interface_name)
        end
        if rest_has_type
          @registered_interfaces.unshift(rest_type_interface_name)
        end
      end
      @registered_interfaces
    end

     # clear the list of registered interfaces, perhaps useful in a command subclass
    def clear_registered_interfaces()
      @registered_interfaces = []
    end

  end

  def rest_name
    self.class.rest_name
  end

  def rest_key
    self.class.rest_key
  end

  def rest_arg
    self.class.rest_arg
  end

  def rest_label
    self.class.rest_label
  end

  def rest_label_plural
    self.class.rest_label_plural
  end

  def rest_interface_name
    self.class.rest_interface_name
  end

  # returns the default rest interface, allows using rest_interface_name = "your"
  # or override this method to return @your_interface if needed
  def rest_interface
    instance_variable_get("@#{rest_interface_name}_interface")
  end

  def rest_object_key
    self.send("#{rest_key}_object_key")
  end

  def rest_list_key
    self.send("#{rest_key}_list_key")
  end

  def rest_column_definitions
    self.send("#{rest_key}_column_definitions")
  end

  def rest_list_column_definitions
    self.send("#{rest_key}_list_column_definitions")
  end

  def rest_find_by_name_or_id(name)
    return self.send("find_#{rest_key}_by_name_or_id", name)
  end

  def rest_has_type
    self.class.rest_has_type
  end

  ## duplicated the rest_* settings with rest_type, for the types resource

  def rest_type_name
    self.class.rest_type_name
  end

  def rest_type_key
    self.class.rest_type_key
  end

  def rest_type_arg
    self.class.rest_type_arg
  end

  def rest_type_label
    self.class.rest_type_label
  end

  def rest_type_label_plural
    self.class.rest_type_label_plural
  end

  def rest_type_interface_name
    self.class.rest_type_interface_name # || "@#{rest_type_name}_interface"
  end

  def rest_type_interface
    instance_variable_get("@#{rest_type_interface_name}_interface")
  end

  def rest_type_object_key
    self.send("#{rest_type_key}_object_key")
  end

  def rest_type_list_key
    self.send("#{rest_type_key}_list_key")
  end

  def rest_type_column_definitions
    self.send("#{rest_type_key}_column_definitions")
  end

  def rest_type_list_column_definitions
    self.send("#{rest_type_key}_list_column_definitions")
  end

  def rest_type_find_by_name_or_id(name)
    return self.send("find_#{rest_type_key}_by_name_or_id", name)
  end

  def registered_interfaces
    self.class.registered_interfaces
  end

  # standard connect method to establish @api_client
  # and @{name}_interface variables for each registered interface.
  def connect(options)
    @api_client = establish_remote_appliance_connection(options)
    self.class.registered_interfaces.each do |interface_name|
      if interface_name.is_a?(String) || interface_name.is_a?(Symbol)
        instance_variable_set("@#{interface_name}_interface", @api_client.send(interface_name))
      elsif interface_name.is_a?(Hash)
        interface_name.each do |k,v|
          instance_variable_set("#{k}_interface", @api_client.send(v))
        end
      end
    end
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
            opts.footer = <<-EOT
List #{rest_label_plural.downcase}.
[search] is optional. This is a search phrase to filter the results.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.list(params)
      return
    end
    json_response = rest_interface.list(params)
    render_response(json_response, options, rest_list_key) do
      records = json_response[rest_list_key]
      print_h1 "Morpheus #{rest_label_plural}"
      if records.nil? || records.empty?
        print cyan,"No #{rest_label_plural.downcase} found.",reset,"\n"
      else
        print as_pretty_table(records, rest_list_column_definitions.upcase_keys!, options)
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
      opts.banner = subcommand_usage("[#{rest_arg}]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about #{a_or_an(rest_label)} #{rest_label.downcase}.
[#{rest_arg}] is required. This is the name or id of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    if id !~ /\A\d{1,}\Z/
      record = rest_find_by_name_or_id(id)
      if record.nil?
        raise_command_error "#{rest_label} not found for name '#{id}'"
      end
      id = record['id']
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.get(id, params)
      return
    end
    json_response = rest_interface.get(id, params)
    render_response_for_get(json_response, options)
    return 0, nil
  end

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions, record, options)
      # show config settings...
      if record['optionTypes'] && record['optionTypes'].size > 0
        print_h2 "Option Types", options
        print format_option_types_table(record['optionTypes'], options, rest_object_key)
      end
      print reset,"\n"
    end
  end

  def add(args)
    record_type_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      if rest_has_type
        opts.banner = subcommand_usage("[#{rest_arg}] -t TYPE")
        opts.on( '-t', "--#{rest_type_arg} TYPE", "#{rest_type_label}" ) do |val|
          record_type_id = val
        end
      else
        opts.banner = subcommand_usage("[#{rest_arg}]")
      end
      # if defined?(add_#{rest_key}_option_types)
      #   build_option_type_options(opts, options, add_#{rest_key}_option_types)
      # end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new #{rest_label.downcase}.
[#{rest_arg}] is required. This is the name of the new #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    # todo: make supporting args[0] optional and more flexible
    # for now args[0] is assumed to be the 'name'
    record_name = nil
    if args[0] # && rest_has_name
      record_name = args[0]
    end
    verify_args!(args:args, optparse:optparse, min:0, max: 1)
    # todo: maybe need a flag to make this required, it could be an option type too, so
    if rest_has_type
      if record_type_id.nil?
        raise_command_error "#{rest_type_label} is required.\n#{optparse}"
      end
    end
    connect(options)
    if rest_has_type
      record_type = rest_type_find_by_name_or_id(record_type_id)
      if record_type.nil?
        raise_command_error "#{rest_type_label} not found for '#{record_type_id}'.\n#{optparse}"
      end
    end
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options})
    else
      record_payload = {}
      if record_name
        record_payload['name'] = record_name
        options[:options]['name'] = record_name # injected for prompt
      end
      if rest_has_type && record_type
        # record_payload['type'] = {'code' => record_type['code']}
        record_payload['type'] = record_type['code']
        options[:options]['type'] = record_type['code'] # injected for prompt
      end
      record_payload.deep_merge!(passed_options)
      # options by type
      my_option_types = record_type ? record_type['optionTypes'] : nil
      if my_option_types && !my_option_types.empty?
        # remove redundant fieldContext
        my_option_types.each do |option_type| 
          if option_type['fieldContext'] == rest_object_key
            option_type['fieldContext'] = nil
          end
        end
        v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.create(payload)
      return
    end      
    json_response = rest_interface.create(payload)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_green_success "Added #{rest_label.downcase} #{record['name'] || record['id']}"
      return _get(record["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    id = args[0]
    options = {}
    params = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}] [options]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing #{rest_label.downcase}.
[#{rest_arg}] is required. This is the name or id of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    record = rest_find_by_name_or_id(id)
    passed_options = parse_passed_options(options)
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options}) unless passed_options.empty?
    else
      record_payload = passed_options
      if record_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.update(record['id'], payload)
      return
    end
    json_response = rest_interface.update(record['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "Updated #{rest_label.downcase} #{record['name'] || record['id']}"
      _get(record["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    id = args[0]
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an existing #{rest_label.downcase}.
[#{rest_arg}] is required. This is the name or id of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    record = rest_find_by_name_or_id(id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the #{rest_label.downcase} #{record['name'] || record['id']}?")
      return 9, "aborted"
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.destroy(record['id'])
      return 0, nil
    end
    json_response = rest_interface.destroy(record['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed #{rest_label.downcase} #{record['name'] || record['id']}"
    end
    return 0, nil
  end

end

