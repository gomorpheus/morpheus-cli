# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancers
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, {:types => :lb_types}
  alias_subcommand :details, :get

  def initialize() 
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @load_balancers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).load_balancers
  end


  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :csv, :yaml, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @load_balancers_interface.dry.get(params)
        return
      end
      json_response = @load_balancers_interface.get(params)
      if options[:json]
        if options[:include_fields]
          json_response = {"loadBalancers" => filter_data(json_response["loadBalancers"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["loadBalancers"], options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"loadBalancers" => filter_data(json_response["loadBalancers"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
        return 0
      else
        lbs = json_response['loadBalancers']
        print_h1 "Morpheus Load Balancers"
        if lbs.empty?
          print yellow,"No load balancers found.",reset,"\n"
        else
          columns = [
            {"ID" => 'id'},
            {"Name" => 'name'},
            {"Type" => lambda {|it| it['type'] ? it['type']['name'] : '' } },
            {"Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' } },
            {"Host" => lambda {|it| it['host'] } },
          ]
          print as_pretty_table(lbs, columns, options)
        end
        print reset,"\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :csv, :yaml, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    lb_name = args[0]
    connect(options)
    begin
      if options[:dry_run]
        if lb_name.to_s =~ /\A\d{1,}\Z/
          print_dry_run @load_balancers_interface.dry.get(lb_name.to_i)
        else
          print_dry_run @load_balancers_interface.dry.get({name:lb_name})
        end
        return
      end
      lb = find_lb_by_name_or_id(lb_name)
      exit 1 if lb.nil?
      # refetch
      json_response = @load_balancers_interface.get(lb['id'])
      lb_type = load_balancer_type_for_name_or_id(lb['type']['code'])
      #puts "LB TYPE: #{lb_type}"
      if options[:json]
        puts JSON.pretty_generate({loadBalancer: lb})
        if options[:include_fields]
          json_response = {"loadBalancer" => filter_data(json_response["loadBalancer"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["loadBalancer"], options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"loadBalancer" => filter_data(json_response["loadBalancer"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
        return 0
      else
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
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    lb_name = args[0]
    options = {}
    account_name = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
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
      lb_type = load_balancer_type_for_name_or_id(lb['type']['code'])

      #params = Morpheus::Cli::OptionTypes.prompt(add_load_balancer_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
      params = options[:options] || {}

      if params.empty?
        puts optparse
        option_lines = update_task_option_types(lb_type).collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      # todo: fix this...
      #puts "parsed params is : #{params.inspect}"
      lb_keys = ['name']
      changes_payload = (params.select {|k,v| task_keys.include?(k) })
      task_payload = task
      if changes_payload
        task_payload.merge!(changes_payload)
      end
      puts params
      if params['taskOptions']
        task_payload['taskOptions'].merge!(params['taskOptions'])
      end
      payload = {task: task_payload}
      if options[:dry_run]
        print_dry_run @load_balancers_interface.dry.update(task['id'], payload)
        return
      end
      response = @load_balancers_interface.update(task['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        if !response['success']
          exit 1
        end
      else
        print "\n", cyan, "Task #{response['task']['name']} updated", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def lb_types(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      if options[:dry_run]
        print_dry_run @load_balancers_interface.dry.load_balancer_types()
        return
      end
      json_response = @load_balancers_interface.load_balancer_types()
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        lb_types = json_response['loadBalancerTypes']
        print_h1 "Morpheus Load Balancer Types"
        if lb_types.nil? || lb_types.empty?
          print yellow,"No lb types currently exist on this appliance. This could be a seed issue.",reset,"\n"
        else
          print cyan
          lb_table_data = lb_types.collect do |lb_type|
            {name: lb_type['name'], id: lb_type['id'], code: lb_type['code']}
          end
          tp lb_table_data, :id, :name, :code
        end

        print reset,"\n"
      end
          rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # JD: This is broken.. copied from tasks? should optionTypes exist?
  def add(args)
    lb_type_name = nil
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] -t LB_TYPE")
      opts.on( '-t', '--type LB_TYPE', "Load Balancer Type" ) do |val|
        lb_type_name = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    lb_name = args[0]
    if args.count < 1
      puts optparse
      exit 1
    end
    if lb_type_name.nil?
      puts optparse
      exit 1
    end
    connect(options)
    begin
      lb_type = load_balancer_type_for_name_or_id(lb_type_name)
      if lb_type.nil?
        print_red_alert "LB Type #{lb_type_name} not found!"
        exit 1
      end

      payload = {loadBalancer: {name: lb_name, type: {code: lb_type['code'], id: lb_type['id']}}}

      # todo: The options available here are specific by type...
      #input_options = Morpheus::Cli::OptionTypes.prompt(lb_type['optionTypes'],options[:options],@api_client, options[:params])
      json_response = @load_balancers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        print "\n", cyan, "LB #{json_response['loadBalancer']['name']} created successfully", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    lb_name = args[0]
    options = {}
    optparse = OptionParser.new do|opts|
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


  private

  def find_lb_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_lb_by_id(val)
    else
      return find_lb_by_name(val)
    end
  end

  def find_lb_by_id(id)
    begin
      json_response = @load_balancers_interface.get(id.to_i)
      return json_response['loadBalancer']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Load Balancer not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_lb_by_name(name)
    lbs = @load_balancers_interface.get({name: name.to_s})['loadBalancers']
    if lbs.empty?
      print_red_alert "Load Balancer not found by name #{name}"
      return nil
    elsif lbs.size > 1
      print_red_alert "#{lbs.size} load balancers found by name #{name}"
      #print_lbs_table(lbs, {color: red})
      print reset,"\n\n"
      return nil
    else
      return lbs[0]
    end
  end

  def get_available_load_balancer_types(refresh=false)
    if !@available_load_balancer_types || refresh
      @available_load_balancer_types = @load_balancers_interface.load_balancer_types['loadBalancerTypes']
    end
    return @available_load_balancer_types
  end

  def load_balancer_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return load_balancer_type_for_id(val)
    else
      return load_balancer_type_for_name(val)
    end
  end

  def load_balancer_type_for_id(id)
    return get_available_load_balancer_types().find { |z| z['id'].to_i == id.to_i}
  end

  def load_balancer_type_for_name(name)
    return get_available_load_balancer_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

end
