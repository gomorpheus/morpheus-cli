# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_name :'load-balancers'
  register_subcommands :list, :get, :add, :update, :remove

  # deprecated the types command in 5.3.2, moved to `load-balancer-types list`
  register_subcommands :types
  set_subcommands_hidden :types

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
      opts.footer = "List load balancers."
    end
    optparse.parse!(args)
    connect(options)
    params.merge!(parse_list_options(options))
    @load_balancers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @load_balancers_interface.dry.list(params)
      return
    end
    json_response = @load_balancers_interface.list(params)
    render_response(json_response, options, 'loadBalancers') do
      lbs = json_response['loadBalancers']
      print_h1 "Morpheus Load Balancers"
      if lbs.empty?
        print cyan,"No load balancers found.",reset,"\n"
      else
        columns = [
          {"ID" => 'id'},
          {"Name" => 'name'},
          {"Type" => lambda {|it| it['type'] ? it['type']['name'] : '' } },
          {"Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' } },
          {"Host" => lambda {|it| it['host'] } },
        ]
        print as_pretty_table(lbs, columns, options)
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
      opts.banner = subcommand_usage("[lb]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific load balancer.
[lb] is required. This is the name or id of a load balancer.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    # lookup IDs if names are given
    id_list = id_list.collect do |id|
      if id.to_s =~ /\A\d{1,}\Z/
        id
      else
        load_balancer = find_lb_by_name_or_id(id)
        if load_balancer
          load_balancer['id'].to_s
        else
          #raise_command_error "load balancer not found for name '#{id}'"
          exit 1
        end
      end
    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    params = {}.merge!(parse_query_options(options))
    @load_balancers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @load_balancers_interface.dry.get(id.to_i)
      return
    end
    json_response = @load_balancers_interface.get(id.to_i)
    render_response(json_response, options, load_balancer_object_key) do
      lb = json_response[load_balancer_object_key]
      #lb_type = load_balancer_type_for_name_or_id(lb['type']['code'])
      print_h1 "Load Balancer Details"
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Visibility" => 'visibility',
        "IP" => 'ip',
        "Host" => 'host',
        "Port" => 'port',
        "Username" => 'username',
        # "SSL Enabled" => lambda {|it| format_boolean it['sslEnabled'] },
        # "SSL Cert" => lambda {|it| it['sslCert'] ? it['sslCert']['name'] : '' },
        # "SSL" => lambda {|it| it['sslEnabled'] ? "Yes (#{it['sslCert'] ? it['sslCert']['name'] : 'none'})" : "No" },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, lb)

      if lb['ports'] && lb['ports'].size > 0
        print_h2 "LB Ports"
        columns = [
          {"ID" => 'id'},
          {"Name" => 'name'},
          #{"Description" => 'description'},
          {"Port" => lambda {|it| it['port'] } },
          {"Protocol" => lambda {|it| it['proxyProtocol'] } },
          {"SSL" => lambda {|it| it['sslEnabled'] ? "Yes (#{it['sslCert'] ? it['sslCert']['name'] : 'none'})" : "No" } },
        ]
        print as_pretty_table(lb['ports'], columns, options)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    lb_type_name = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -t LB_TYPE")
      opts.on( '-t', '--type CODE', "Load Balancer Type" ) do |val|
        lb_type_name = val
      end
      #build_option_type_options(opts, options, add_load_balancer_option_types)
      build_standard_add_options(opts, options)
    end
    optparse.parse!(args)
    lb_name = args[0]
    # verify_args!(args:args, optparse:optparse, min:0, max: 1)
    verify_args!(args:args, optparse:optparse, min:1, max: 1)
    if lb_type_name.nil?
      raise_command_error "Load Balancer Type is required.\n#{optparse}"
      puts optparse
      exit 1
    end
    connect(options)
    lb_type = load_balancer_type_for_name_or_id(lb_type_name)
    if lb_type.nil?
      print_red_alert "LB Type #{lb_type_name} not found!"
      exit 1
    end
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({load_balancer_object_key => passed_options})
    else
      load_balancer_payload = {'name' => lb_name, 'type' => {'code' =>  lb_type['code'], 'id' => lb_type['id']}}
      load_balancer_payload.deep_merge!({load_balancer_object_key => passed_options})
      # options by type
      my_option_types = lb_type['optionTypes']
      if my_option_types && !my_option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        load_balancer_payload.deep_merge!(v_prompt)
      end
      payload[load_balancer_object_key] = load_balancer_payload
    end
    @load_balancers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @load_balancers_interface.dry.create(payload)
      return
    end      
    json_response = @load_balancers_interface.create(payload)
    render_response(json_response, options, load_balancer_object_key) do
      load_balancer = json_response[load_balancer_object_key]
      print_green_success "Added load balancer #{load_balancer['name']}"
      return _get(load_balancer["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    lb_name = args[0]
    options = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[lb] [options]")
      build_standard_update_options(opts, options)
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    passed_options = parse_passed_options(options)
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({load_balancer_object_key => passed_options}) unless passed_options.empty?
    else
      load_balancer_payload = passed_options
      if tenants_list
        load_balancer_payload['accounts'] = tenants_list
      end
      # metadata tags
      if options[:tags]
        load_balancer_payload['tags'] = parse_metadata(options[:tags])
      else
        # tags = prompt_metadata(options)
        # payload[load_balancer_object_key]['tags'] = tags of tags
      end
      # metadata tags
      if options[:add_tags]
        load_balancer_payload['addTags'] = parse_metadata(options[:add_tags])
      end
      if options[:remove_tags]
        load_balancer_payload['removeTags'] = parse_metadata(options[:remove_tags])
      end
      if load_balancer_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload = {'virtualImage' => load_balancer_payload}
    end
    @load_balancers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @load_balancers_interface.dry.update(load_balancer['id'], payload)
      return
    end
    json_response = @load_balancers_interface.update(load_balancer['id'], payload)
    render_response(json_response, options, 'virtualImage') do
      print_green_success "Updated virtual image #{load_balancer['name']}"
      _get(load_balancer["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    lb_name = args[0]
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      lb = find_lb_by_name_or_id(lb_name)
      exit 1 if lb.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the load balancer #{lb['name']}?")
        exit
      end
      @load_balancers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @load_balancers_interface.dry.destroy(lb['id'])
        return
      end
      json_response = @load_balancers_interface.destroy(lb['id'])
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
      else
        print "\n", cyan, "Load Balancer #{lb['name']} removed", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def types(args)
    print_error yellow,"[DEPRECATED] The command `load-balancers types` is deprecated. It has been replaced by `load-balancer-types list`.",reset,"\n"
    my_terminal.execute("load-balancer-types list #{args.join(' ')}")
  end

  private

  # finders are in the LoadBalancerHelper mixin  

end
