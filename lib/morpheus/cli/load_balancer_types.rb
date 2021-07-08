# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_name :'load-balancer-types'
  register_subcommands :list, :get

  def initialize() 
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @load_balancers_interface = @api_client.load_balancers
    @load_balancer_types_interface = @api_client.load_balancer_types
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
      opts.footer = "List load balancer types."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @load_balancers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @load_balancer_types_interface.dry.list(params)
      return
    end
    json_response = @load_balancer_types_interface.list(params)
    render_response(json_response, options, 'loadBalancerTypes') do
      load_balancer_types = json_response['loadBalancerTypes']
      print_h1 "Morpheus Load Balancer Types"
      if load_balancer_types.nil? || load_balancer_types.empty?
        print cyan,"No load balancer types found.",reset,"\n"
      else
        print as_pretty_table(load_balancer_types, load_balancer_type_list_column_definitions.upcase_keys!, options)
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
Get details about a load balancer type.
[type] is required. This is the name, code or id of a load balancer type.
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
      # load_balancer_type = find_load_balancer_type_by_name_or_id(id)
      load_balancer_type = load_balancer_type_for_name_or_id(id)
      if load_balancer_type.nil?
        raise_command_error "Load balancer type not found for name or code '#{id}'"
      end
      id = load_balancer_type['id']
    end
    @load_balancer_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @load_balancer_types_interface.dry.get(id, params)
      return
    end
    json_response = @load_balancer_types_interface.get(id, params)
    
    render_response(json_response, options, load_balancer_type_object_key) do
      load_balancer_type = json_response["loadBalancerType"]
      print_h1 "Load Balancer Type", [], options
      print cyan
      print_description_list(load_balancer_type_column_definitions, load_balancer_type, options)

      # show config settings...
      if load_balancer_type['optionTypes'] && load_balancer_type['optionTypes'].size > 0
        print_h2 "Configuration Option Types"
        print format_option_types_table(load_balancer_type['optionTypes'], options, load_balancer_object_key)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  private

  def load_balancer_type_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code'
    }
  end

  def load_balancer_type_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code'
    }
  end

  # finders are in the LoadBalancerHelper mixin

end

