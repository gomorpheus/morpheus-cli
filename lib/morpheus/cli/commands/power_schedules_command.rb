require 'morpheus/cli/cli_command'

class Morpheus::Cli::PowerSchedulesCommand
  include Morpheus::Cli::CliCommand
  # include Morpheus::Cli::ProvisioningHelper
  set_command_name :'power-schedules'

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :'add-instances' => :add_instances
  register_subcommands :'remove-instances' => :remove_instances
  register_subcommands :'add-hosts' => :add_hosts
  register_subcommands :'remove-hosts' => :remove_hosts
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @power_schedules_interface = @api_client.power_schedules
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = "List power schedules."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @power_schedules_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @power_schedules_interface.dry.list(params)
      return
    end
    json_response = @power_schedules_interface.list(params)
    render_response(json_response, options, power_schedule_list_key) do
      power_schedules = json_response[power_schedule_list_key]
      print_h1 "Morpheus Power Schedules", parse_list_subtitles(options), options
      if power_schedules.empty?
        print cyan,"No power schedules found.",reset,"\n"
      else
        print as_pretty_table(power_schedules, power_schedule_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end
  
  def get(args)
    params = {}
    options = {}
    options[:max_instances] = 10
    options[:max_servers] = 10
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[schedule]")
      opts.on('--max-instances VALUE', String, "Display a limited number of instances in schedule. Default is 10") do |val|
        options[:max_instances] = val.to_i
      end
      opts.on('--max-hosts VALUE', String, "Display a limited number of hosts in schedule. Default is 10") do |val|
        options[:max_servers] = val.to_i
      end
      build_standard_get_options(opts, options)
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
    options ||= {}
    options[:max_servers] ||= 10
    options[:max_instances] ||= 10
    
    schedule = find_schedule_by_name_or_id(id)
    if schedule.nil?
      return 1
    end
    @power_schedules_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @power_schedules_interface.dry.get(schedule['id'], params)
      return
    end
    json_response = @power_schedules_interface.get(schedule['id'], params)
    render_response(json_response, options, power_schedule_object_key) do
      schedule = json_response[power_schedule_object_key]
      instances = json_response['instances'] || []
      servers = json_response['servers'] || []
      
      print_h1 "Power Schedule Details"
      print cyan
      print_description_list(power_schedule_column_definitions(options), schedule, options)

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
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {'scheduleType' => 'power'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, add_power_schedule_option_types)
      build_standard_add_options(opts, options)
      opts.footer = "Create a new power schedule." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    # support [name] as first argument
    if args[0]
      options[:options]['name'] = args[0]
    end
    connect(options)
    begin
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'schedule' => parse_passed_options(options)})
      else
        # merge -O options into normally parsed options
        payload.deep_merge!({'schedule' => parse_passed_options(options)})
        # prompt
        schedule_payload = Morpheus::Cli::OptionTypes.prompt(add_power_schedule_option_types, options[:options], @api_client, options[:params])
        payload.deep_merge!({'schedule' => schedule_payload})
        payload.booleanize!
      end
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.create(payload)
        return
      end
      json_response = @power_schedules_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        schedule = json_response['schedule']
        print_green_success "Added power schedule #{schedule['name']}"
        _get(schedule['id'], {}, options)
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
      opts.banner = subcommand_usage("[schedule]")
      build_option_type_options(opts, options, update_power_schedule_option_types)
      build_standard_add_options(opts, options)
      opts.footer = "Update a power schedule." + "\n" +
                    "[schedule] is required. This is the name or id of a power schedule."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'schedule' => parse_passed_options(options)})
      else
        # merge -O options into normally parsed options
        payload.deep_merge!({'schedule' => parse_passed_options(options)})
        # prompt
        schedule_payload = Morpheus::Cli::OptionTypes.no_prompt(update_power_schedule_option_types, options[:options], @api_client, options[:params])
        payload.deep_merge!({'schedule' => schedule_payload})
        payload.booleanize!
      end
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.update(schedule["id"], payload)
        return
      end
      json_response = @power_schedules_interface.update(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated power schedule #{schedule['name']}"
        _get(schedule['id'], {}, options)
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
      opts.banner = subcommand_usage("[schedule]")
      build_standard_remove_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete power schedule '#{schedule['name']}'?", options)
        return false
      end

      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.destroy(schedule["id"])
        return
      end

      json_response = @power_schedules_interface.destroy(schedule["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted power schedule #{schedule['name']}"
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
      opts.banner = subcommand_usage("[schedule] [instance]")
      build_standard_update_options(opts, options)
      opts.footer = "Assign instances to a power schedule.\n" +
                    "[schedule] is required. This is the name or id of a power schedule.\n" +
                    "[instance] is required. This is the name or id of an instance. More than one can be passed."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        instance_ids = args[1..-1]
        instances = []
        instance_ids.each do |instance_id|
          instance = find_instance_by_name_or_id(instance_id)
          return 1 if instance.nil?
          instances << instance
        end
        payload.deep_merge!({'instances' => instances.collect {|it| it['id'] } })
      end
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.add_instances(schedule["id"], payload)
        return 0
      end
      json_response = @power_schedules_interface.add_instances(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
            print_green_success  "Added #{instances[0]['name']} to power schedule #{schedule['name']}"
          else
            print_green_success "Added #{instances.size} instances to power schedule #{schedule['name']}"
          end
        _get(schedule['id'], {}, options)
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
      opts.banner = subcommand_usage("[schedule] [instance]")
      build_standard_update_options(opts, options)
      opts.footer = "Remove instances from a power schedule.\n" +
                    "[schedule] is required. This is the name or id of a power schedule.\n" +
                    "[instance] is required. This is the name or id of an instance. More than one can be passed."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        instance_ids = args[1..-1]
        instances = []
        instance_ids.each do |instance_id|
          instance = find_instance_by_name_or_id(instance_id)
          return 1 if instance.nil?
          instances << instance
        end
        payload.deep_merge!({'instances' => instances.collect {|it| it['id'] } })
      end
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.remove_instances(schedule["id"], payload)
        return 0
      end
      json_response = @power_schedules_interface.remove_instances(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
            print_green_success  "Removed instance #{instances[0]['name']} from power schedule #{schedule['name']}"
          else
            print_green_success "Removed #{instances.size} instances from power schedule #{schedule['name']}"
          end
        _get(schedule['id'], {}, options)
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
      opts.banner = subcommand_usage("[schedule] [host]")
      build_standard_update_options(opts, options)
      opts.footer = "Assign hosts to a power schedule.\n" +
                    "[schedule] is required. This is the name or id of a power schedule.\n" +
                    "[host] is required. This is the name or id of a host. More than one can be passed."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        server_ids = args[1..-1]
        servers = []
        server_ids.each do |server_id|
          server = find_server_by_name_or_id(server_id)
          return 1 if server.nil?
          servers << server
        end
        payload.deep_merge!({'servers' => servers.collect {|it| it['id'] } })
      end
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.add_servers(schedule["id"], payload)
        return 0
      end
      json_response = @power_schedules_interface.add_servers(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if servers.size == 1
            print_green_success  "Added host #{servers[0]['name']} to power schedule #{schedule['name']}"
          else
            print_green_success "Added #{servers.size} hosts to power schedule #{schedule['name']}"
          end
        _get(schedule['id'], {}, options)
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
      opts.banner = subcommand_usage("[schedule] [host]")
      build_standard_update_options(opts, options)
      opts.footer = "Remove hosts from a power schedule.\n" +
                    "[schedule] is required. This is the name or id of a power schedule.\n" +
                    "[host] is required. This is the name or id of a host. More than one can be passed."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    begin
      schedule = find_schedule_by_name_or_id(args[0])
      if schedule.nil?
        return 1
      end

      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        server_ids = args[1..-1]
        servers = []
        server_ids.each do |server_id|
          server = find_server_by_name_or_id(server_id)
          return 1 if server.nil?
          servers << server
        end
        payload.deep_merge!({'servers' => servers.collect {|it| it['id'] } })
      end
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.remove_servers(schedule["id"], payload)
        return 0
      end
      json_response = @power_schedules_interface.remove_servers(schedule["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if servers.size == 1
            print_green_success  "Removed host #{servers[0]['name']} from power schedule #{schedule['name']}"
          else
            print_green_success "Removed #{servers.size} hosts from power schedule #{schedule['name']}"
          end
        _get(schedule['id'], {}, options)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def power_schedule_object_key
    'schedule'
  end

  def power_schedule_list_key
    'schedules'
  end

  def power_schedule_list_column_definitions(options)
    {
      "ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['name'] },
      "Description" => lambda {|it| it['description'] },
      "Type" => lambda {|it| format_schedule_type(it['scheduleType']) }
    }
  end

  def power_schedule_column_definitions(options)
    {
      "ID" => lambda {|it| it['id'] },
      #"Account" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      "Name" => lambda {|it| it['name'] },
      "Description" => lambda {|it| it['description'] },
      "Type" => lambda {|it| format_schedule_type(it['scheduleType']) },
      "Enabled" => lambda {|it| format_boolean it['enabled'] },
      "Time Zone" => lambda {|it| it['scheduleTimezone'] || 'UTC (default)' },
      "Monday" => lambda {|it| format_schedule_day(it, "monday")},
      "Tuesday" => lambda {|it| format_schedule_day(it, "tuesday") },
      "Wednesday" => lambda {|it| format_schedule_day(it, "wednesday") },
      "Thursday" => lambda {|it| format_schedule_day(it, "thursday") },
      "Friday" => lambda {|it| format_schedule_day(it, "friday") },
      "Saturday" => lambda {|it| format_schedule_day(it, "saturday") },
      "Sunday" => lambda {|it| format_schedule_day(it, "sunday") },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def add_power_schedule_option_types()
    option_list = [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Choose a unique name for the power schedule', 'fieldGroup' => 'Options', 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Description', 'displayOrder' => 2},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'displayOrder' => 3},
      {'fieldName' => 'scheduleTimezone', 'fieldLabel' => 'Time Zone', 'type' => 'select', 'optionSource' => 'timezones', 'description' => "Time Zone", 'displayOrder' => 4}, #, 'defaultValue' => Time.now.zone
      {'fieldName' => 'scheduleType', 'fieldLabel' => 'Schedule Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Power On', 'value' => 'power'}, {'name' => 'Power Off', 'value' => 'power off'}], 'defaultValue' => 'power', 'description' => "Type of Power Schedule 'power' or 'power off'", 'displayOrder' => 5},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true, 'description' => 'Enable the power schedule to make it available for use.', 'displayOrder' => 6},
    ]
    [
      'monday','tuesday','wednesday','thursday','friday','saturday','sunday'
    ].each_with_index do |day, i|
      option_list << {'fieldName' => "#{day}OnTime", 'fieldLabel' => "#{day.capitalize} Start", 'type' => 'text', 'placeHolder' => 'HH:MM', 'description' => "#{day.capitalize} start time in HH:MM 24-hour format", 'defaultValue' => "00:00", 'displayOrder' => 7+((i*2))}
      option_list << {'fieldName' => "#{day}OffTime", 'fieldLabel' => "#{day.capitalize} End", 'type' => 'text', 'placeHolder' => 'HH:MM', 'description' => "#{day.capitalize} end time in HH:MM 24-hour format", 'defaultValue' => "24:00", 'displayOrder' => 7+((i*2)+1)}
    end
    return option_list
  end

  def update_power_schedule_option_types()
    option_list = add_power_schedule_option_types
    option_list.each do |option_type|
      option_type.delete('required')
      option_type.delete('defaultValue')
    end
    return option_list
  end

  def find_schedule_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_schedule_by_id(val)
    else
      return find_schedule_by_name(val)
    end
  end

  def find_schedule_by_id(id)
    begin
      json_response = @power_schedules_interface.get(id.to_i)
      return json_response['schedule']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Power Schedule not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_schedule_by_name(name)
    schedules = @power_schedules_interface.list({name: name.to_s})['schedules']
    if schedules.empty?
      print_red_alert "Power Schedule not found by name #{name}"
      return nil
    elsif schedules.size > 1
      print_red_alert "#{schedules.size} power schedules found by name #{name}"
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
      {"TYPE" => lambda {|schedule| format_schedule_type(schedule['scheduleType']) } },
      #{"TIMES" => lambda {|schedule| format_schedule_days_short(schedule) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(schedules, columns, opts)
  end

  def format_schedule_type(val)
    case val.to_s.downcase
    when "power" then "Power On"
    when "power off" then "Power Off"
    else
      val.to_s #.capitalize
    end
  end

  # format day on - off times in HH:MM - HH:MM
  def format_schedule_day(schedule, day)
    # API used to only return On/Off but now returns OnTime/OffTime
    if schedule[day + 'OnTime']
      schedule[day + 'OnTime'].to_s + ' - ' + schedule[day + 'OffTime'].to_s
    elsif schedule[day + 'On']
      schedule_hour_to_time(schedule[day + 'On']) + ' - ' + schedule_hour_to_time(schedule[day + 'Off'])
    else
      "" #"bad day"
    end
  end

  # convert the schedule on/off minute values [0-1440] to a time
  # older versions used hours 0-24 instead of minutes
  def schedule_hour_to_time(val)
    hour = val.to_f.floor
    remainder = val.to_f % 1
    minute = remainder == 0 ? 0 : (60 * remainder).floor
    "#{hour.to_s.rjust(2,'0')}:#{minute.to_s.rjust(2,'0')}"
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
    instances = @instances_interface.list({name: name.to_s})['instances']
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
