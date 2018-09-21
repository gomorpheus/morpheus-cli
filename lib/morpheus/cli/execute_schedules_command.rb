require 'morpheus/cli/cli_command'

class Morpheus::Cli::ExecuteSchedulesCommand
  include Morpheus::Cli::CliCommand
  # include Morpheus::Cli::ProvisioningHelper
  set_command_name :'execute-schedules'

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :'add-instances' => :add_instances
  register_subcommands :'remove-instances' => :remove_instances
  register_subcommands :'add-hosts' => :add_hosts
  register_subcommands :'remove-hosts' => :remove_hosts
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @execute_schedules_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).execute_schedules
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @servers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).servers
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.list(params)
        return
      end
      json_response = @execute_schedules_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "schedules")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['schedules'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "schedules")
        return 0
      end
      schedules = json_response['schedules']
      title = "Morpheus Execute Schedules"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if schedules.empty?
        print cyan,"No execute schedules found.",reset,"\n"
      else
        print_schedules_table(schedules, options)
        print_results_pagination(json_response, {:label => "schedule", :n_label => "schedules"})
        # print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end
  
  def get(args)
    options = {}
    options[:max_instances] = 10
    options[:max_servers] = 10
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--max-instances VALUE', String, "Display a limited number of instances in schedule. Default is 25") do |val|
        options[:max_instances] = val.to_i
      end
      opts.on('--max-hosts VALUE', String, "Display a limited number of hosts in schedule. Default is 25") do |val|
        options[:max_servers] = val.to_i
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    options ||= {}
    options[:max_servers] ||= 10
    options[:max_instances] ||= 10
    begin
      schedule = find_schedule_by_name_or_id(id)
      if schedule.nil?
        return 1
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.get(schedule['id'])
        return
      end
      json_response = @execute_schedules_interface.get(schedule['id'])
      schedule = json_response['schedule']
      instances = json_response['instances'] || []
      servers = json_response['servers'] || []
      if options[:json]
        puts as_json(json_response, options, "schedule")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "schedule")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['schedule']], options)
        return 0
      end

      print_h1 "Execute Schedule Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        #"Account" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        "Type" => lambda {|it| format_schedule_type(it['scheduleType']) },
        "Enabled" => lambda {|it| format_boolean it['enabled'] },
        "Time Zone" => lambda {|it| it['scheduleTimezone'] || 'UTC (default)' },
        "Cron" => lambda {|it| it['cron'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, schedule)

      ## Instances
      if instances.size == 0
        # print cyan,"No instances",reset,"\n"
      else
        print_h2 "Instances (#{instances.size})"
        instance_rows = instances.first(options[:max_instances])
        print as_pretty_table(instance_rows, [:id, :name])
        print_results_pagination({'meta'=>{'total'=>instances.size,'size'=>instance_rows.size,'max'=>options[:max_servers],'offset'=>0}}, {:label => "instance in schedule", :n_label => "instances in schedule"})
      end

      ## Hosts
      if servers.size == 0
        # print cyan,"No hosts",reset,"\n"
      else
        options[:max_servers] ||= 10
        print_h2 "Hosts (#{servers.size})"
        server_rows = servers.first(options[:max_servers])
        print as_pretty_table(server_rows, [:id, :name])
        print_results_pagination({'meta'=>{'total'=>servers.size,'size'=>server_rows.size,'max'=>options[:max_servers],'offset'=>0}}, {:label => "host in schedule", :n_label => "hosts in schedule"})
      end

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {'scheduleType' => 'execute'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      # opts.on('--code VALUE', String, "Code") do |val|
      #   params['code'] = val
      # end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--type [execute]', String, "Type of Schedule. Default is 'execute'") do |val|
        params['scheduleType'] = val
      end
      opts.on('--timezone CODE', String, "The timezone. Default is UTC.") do |val|
        params['scheduleTimezone'] = val
      end
      opts.on('--cron EXPRESSION', String, "Cron Expression. Default is daily at midnight '0 0 * * *'") do |val|
        params['cron'] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
        params['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new execute schedule." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    # support [name] as first argument
    if args[0]
      params['name'] = args[0]
    end
    connect(options)
    begin
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # todo: prompt?
        payload = {'schedule' => params}
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.create(payload)
        return
      end
      json_response = @execute_schedules_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        schedule = json_response['schedule']
        print_green_success "Added execute schedule #{schedule['name']}"
        _get(schedule['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      # opts.on('--code VALUE', String, "Code") do |val|
      #   params['code'] = val
      # end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--type [execute]', String, "Type of Schedule. Default is 'execute'") do |val|
        params['scheduleType'] = val
      end
      opts.on('--timezone CODE', String, "The timezone. Default is UTC.") do |val|
        params['scheduleTimezone'] = val
      end
      opts.on('--cron EXPRESSION', String, "Cron Expression") do |val|
        params['cron'] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
        params['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a execute schedule." + "\n" +
                    "[name] is required. This is the name or id of a execute schedule."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload = {'schedule' => params}
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.update(schedule["id"], payload)
        return
      end
      json_response = @execute_schedules_interface.update(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated execute schedule #{schedule['name']}"
        _get(schedule['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :auto_confirm])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete execute schedule '#{schedule['name']}'?", options)
        return false
      end

      # payload = {
      #   'schedule' => {id: schedule["id"]}
      # }
      # payload['schedule'].merge!(schedule)
      payload = params

      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.destroy(schedule["id"])
        return
      end

      json_response = @execute_schedules_interface.destroy(schedule["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted execute schedule #{schedule['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add_instances(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [instance]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Assign instances to a execute schedule.\n" +
                    "[name] is required. This is the name or id of a execute schedule.\n" +
                    "[instance] is required. This is the name or id of an instance. More than one can be passed."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      return 1
    end
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        instance_ids = args[1..-1]
        instances = []
        instance_ids.each do |instance_id|
          instance = find_instance_by_name_or_id(instance_id)
          return 1 if instance.nil?
          instances << instance
        end
        payload = {'instances' => instances.collect {|it| it['id'] } }
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.add_instances(schedule["id"], payload)
        return 0
      end
      json_response = @execute_schedules_interface.add_instances(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
            print_green_success  "Added #{instances[0]['name']} to execute schedule #{schedule['name']}"
          else
            print_green_success "Added #{instances.size} instances to execute schedule #{schedule['name']}"
          end
        _get(schedule['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_instances(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [instance]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Remove instances from a execute schedule.\n" +
                    "[name] is required. This is the name or id of a execute schedule.\n" +
                    "[instance] is required. This is the name or id of an instance. More than one can be passed."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      return 1
    end
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        instance_ids = args[1..-1]
        instances = []
        instance_ids.each do |instance_id|
          instance = find_instance_by_name_or_id(instance_id)
          return 1 if instance.nil?
          instances << instance
        end
        payload = {'instances' => instances.collect {|it| it['id'] } }
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.remove_instances(schedule["id"], payload)
        return 0
      end
      json_response = @execute_schedules_interface.remove_instances(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
            print_green_success  "Removed instance #{instances[0]['name']} from execute schedule #{schedule['name']}"
          else
            print_green_success "Removed #{instances.size} instances from execute schedule #{schedule['name']}"
          end
        _get(schedule['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add_hosts(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [host]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Assign hosts to a execute schedule.\n" +
                    "[name] is required. This is the name or id of a execute schedule.\n" +
                    "[host] is required. This is the name or id of a host. More than one can be passed."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      return 1
    end
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        server_ids = args[1..-1]
        servers = []
        server_ids.each do |server_id|
          server = find_server_by_name_or_id(server_id)
          return 1 if server.nil?
          servers << server
        end
        payload = {'servers' => servers.collect {|it| it['id'] } }
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.add_servers(schedule["id"], payload)
        return 0
      end
      json_response = @execute_schedules_interface.add_servers(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if servers.size == 1
            print_green_success  "Added host #{servers[0]['name']} to execute schedule #{schedule['name']}"
          else
            print_green_success "Added #{servers.size} hosts to execute schedule #{schedule['name']}"
          end
        _get(schedule['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_hosts(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [host]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Remove hosts from a execute schedule.\n" +
                    "[name] is required. This is the name or id of a execute schedule.\n" +
                    "[host] is required. This is the name or id of a host. More than one can be passed."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      return 1
    end
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        server_ids = args[1..-1]
        servers = []
        server_ids.each do |server_id|
          server = find_server_by_name_or_id(server_id)
          return 1 if server.nil?
          servers << server
        end
        payload = {'servers' => servers.collect {|it| it['id'] } }
      end
      if options[:dry_run]
        print_dry_run @execute_schedules_interface.dry.remove_servers(schedule["id"], payload)
        return 0
      end
      json_response = @execute_schedules_interface.remove_servers(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if servers.size == 1
            print_green_success  "Removed host #{servers[0]['name']} from execute schedule #{schedule['name']}"
          else
            print_green_success "Removed #{servers.size} hosts from execute schedule #{schedule['name']}"
          end
        _get(schedule['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def find_schedule_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_schedule_by_id(val)
    else
      return find_schedule_by_name(val)
    end
  end

  def find_schedule_by_id(id)
    begin
      json_response = @execute_schedules_interface.get(id.to_i)
      return json_response['schedule']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Execute Schedule not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_schedule_by_name(name)
    schedules = @execute_schedules_interface.list({name: name.to_s})['schedules']
    if schedules.empty?
      print_red_alert "Execute Schedule not found by name #{name}"
      return nil
    elsif schedules.size > 1
      print_red_alert "#{schedules.size} execute schedules found by name #{name}"
      print_schedules_table(schedules, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return schedules[0]
    end
  end

  def print_schedules_table(schedules, opts={})
    columns = [
      {"ID" => lambda {|schedule| schedule['id'] } },
      {"NAME" => lambda {|schedule| schedule['name'] } },
      {"DESCRIPTION" => lambda {|schedule| schedule['description'] } },
      {"CRON" => lambda {|schedule| schedule['cron'] } },
      #{"TYPE" => lambda {|schedule| format_schedule_type(schedule['scheduleType']) } },
      #{"TIMES" => lambda {|schedule| format_schedule_days_short(schedule) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(schedules, columns, opts)
  end

  def format_schedule_type(val)
    case val.to_s.downcase
    when "execute" then "Execute"
    else
      val.to_s #.capitalize
    end
  end

  def find_instance_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_instance_by_id(val)
    else
      return find_instance_by_name(val)
    end
  end

  def find_instance_by_id(id)
    begin
      json_response = @instances_interface.get(id.to_i)
      return json_response['instance']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_instance_by_name(name)
    instances = @instances_interface.get({name: name.to_s})['instances']
    if instances.empty?
      print_red_alert "Instance not found by name #{name}"
      return nil
    elsif instances.size > 1
      print_red_alert "#{instances.size} instances found by name #{name}"
      as_pretty_table(instances, [:id, :name], {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return instances[0]
    end
  end

  def find_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_server_by_id(val)
    else
      return find_server_by_name(val)
    end
  end

  def find_server_by_id(id)
    begin
      json_response = @servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Server not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_server_by_name(name)
    servers = @servers_interface.list({name: name.to_s})['servers']
    if servers.empty?
      print_red_alert "Host not found by name #{name}"
      return nil
    elsif servers.size > 1
      print_red_alert "#{servers.size} hosts found by name #{name}"
      as_pretty_table(servers, [:id, :name], {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return servers[0]
    end
  end

end
