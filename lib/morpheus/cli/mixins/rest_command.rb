# require 'morpheus/cli/cli_command'
# Mixin for Morpheus::Cli command classes
# Provides common methods for basic crud actions: list, get, add, update, remove
# The command class must define a few settings such as:
# class Morpheus::Cli::LoadBalancers
#   set_object_label "Load Balancer"
#   set_plural_label "Load Balancers"
#   set_object_key "load_balancer"
#   set_has_type true
#   set_type_object_key "load_balancer_type"
#   register_interfaces :load_balancers, :load_balancer_types
module Morpheus::Cli::RestCommand

  def self.included(klass)
    klass.send :include, Morpheus::Cli::CliCommand
    klass.extend ClassMethods
  end

  module ClassMethods

    # set the rest name (plural), used for looking up variables used in the default CRUD commands eg. "load_balancers"
    def rest_name=(rest_name)
      @rest_name = rest_name
    end

    alias :set_rest_name :rest_name=

    # the default rest name eg. LoadBalancersCommand is "load_balancers"
    def default_rest_name
      self.command_name.to_s.gsub("-", "_")
    end
    
    def rest_name
      @rest_name || default_rest_name
    end

    # set the rest key, used for looking up properties that begin with the singular name as a prefix eg. load_balancer_column_definitions
    # by default this is the singular version of the rest_name
    def rest_key=(v)
      @rest_key = v
    end

    # the default key (singular name) eg. LoadBalancersCommand is "load_balancer"
    def default_rest_key
      rest_name.chomp("s")
    end
    
    def rest_key
      @rest_key || default_rest_key
    end

    alias :set_rest_key :rest_key=

    def rest_label=(v)
      @rest_label = v
    end

    # the default label eg. "Load Balancer"
    def default_rest_label
      # self.command_name.to_s.split("-").collect {|it| it.to_s.capitalize }.join(" ")
      rest_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end
    
    def rest_label
      @rest_label || default_rest_label
    end

    alias :set_rest_label :rest_label=

    def rest_plural_label=(v)
      @rest_plural_label = v
    end

    # the default plural label eg. "Load Balancers"
    def default_rest_plural_label
      # self.command_name.to_s.split("-").collect {|it| it.to_s.capitalize }.join(" ")
      label = rest_label
      if label[-1].chr == "y"
        label = label[0..-2] + "ies"
      elsif label[-1].chr == "s"
        label = label + "es"
      else
        label = label + "s"
      end
      label
    end
    
    def rest_plural_label
      @rest_plural_label || default_rest_plural_label
    end

    alias :set_rest_plural_label :rest_plural_label=
    
    def rest_interface_name=(v)
      @rest_interface_name = v
    end

    # the name of the default interface
    def default_rest_interface_name
      rest_name
    end
    
    def rest_interface_name
      @rest_interface_name || default_rest_interface_name
    end

    alias :set_rest_interface_name :rest_interface_name=

    # set list of interface names that are registered for this command
    # The registered interfaces will be pre-loaded into instance variables
    # eg. [:load_balancers, :load_balancer_types] will instantiate
    #     @load_balancers_interfaces and @load_balancer_types_interfaces
    def register_interfaces(*interfaces)
      @registered_interfaces ||= []
      interfaces.flatten.each do |it|
        @registered_interfaces << it.to_sym
      end
      # put the default rest_interface first
      if rest_interface_name && !@registered_interfaces.include?(rest_interface_name)
        @registered_interfaces.unshift(rest_interface_name)
      end
      @registered_interfaces
    end

    alias :register_interface :register_interfaces

    # get list of interface names that are registered for this command
    def registered_interfaces
      @registered_interfaces ||= []
      # put the default rest_interface first
      if @registered_interfaces.empty? && rest_interface_name
        @registered_interfaces.unshift(rest_interface_name)
      end
      @registered_interfaces
    end

  end

  def rest_name
    self.class.rest_name
  end

  def rest_key
    self.class.rest_key
  end

  def rest_label
    self.class.rest_label
  end

  def rest_plural_label
    self.class.rest_plural_label
  end

  def rest_interface_name
    self.class.rest_interface_name # || "@#{rest_name}_interface"
  end

  # returns the default rest interface, allows using rest_interface_name = "your"
  # or override this method to return @your_interface if needed
  def rest_interface
    if rest_interface_name
      instance_variable_get("@#{rest_interface_name}_interface")
    elsif self.class.registered_interfaces.size > 0
      instance_variable_get("@#{self.class.registered_interfaces[0]}_interface")
    else
      instance_variable_get("@#{rest_name}_interface")
    end
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
      opts.banner = subcommand_usage()
      build_standard_list_options(opts, options)
      opts.footer = "List #{rest_plural_label.downcase}."
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
      print_h1 "Morpheus #{rest_plural_label}"
      if records.nil? || records.empty?
        print cyan,"No load balancer types found.",reset,"\n"
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
      opts.banner = subcommand_usage("[type]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a #{rest_label.downcase}.
[type] is required. This is the name, code or id of a #{rest_label.downcase}.
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
        print_h2 "Configuration Option Types", options
        print format_option_types_table(record['optionTypes'], options, rest_object_key)
      end
      print reset,"\n"
    end
  end

  # todo: finish add, update, remove commands here...

end

