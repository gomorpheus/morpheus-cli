# require 'yaml'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_name :'load-balancers'
  register_subcommands :list, :get, :add, :update, :remove

  # deprecated the `load-balancers types` command in 5.3.2, it moved to `load-balancer-types list`
  register_subcommands :types
  set_subcommands_hidden :types

  # RestCommand settings
  register_interfaces :load_balancers, :load_balancer_types
  set_rest_has_type true
  # set_rest_type :load_balancer_types

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions, record, options)
      # show LB Ports
      ports = record['ports']
      if ports && ports.size > 0
        print_h2 "LB Ports", options
        columns = [
          {"ID" => 'id'},
          {"Name" => 'name'},
          #{"Description" => 'description'},
          {"Port" => lambda {|it| it['port'] } },
          {"Protocol" => lambda {|it| it['proxyProtocol'] } },
          {"SSL" => lambda {|it| it['sslEnabled'] ? "Yes (#{it['sslCert'] ? it['sslCert']['name'] : 'none'})" : "No" } },
        ]
        print as_pretty_table(ports, columns, options)
      end
      print reset,"\n"
    end
  end

=begin

# now using RestCommand

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
=end

  # deprecated, to be removed in the future.
  def types(args)
    print_error yellow,"[DEPRECATED] The command `load-balancers types` is deprecated and replaced by `load-balancer-types list`.",reset,"\n"
    my_terminal.execute("load-balancer-types list #{args.join(' ')}")
  end

  protected

  def load_balancer_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
      "Host" => lambda {|it| it['host'] }
    }
  end

  def load_balancer_column_definitions()
    {
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
  end

  # overridden to work with name or code
  def find_load_balancer_type_by_name_or_id(name)
    load_balancer_type_for_name_or_id(name)
  end



end
