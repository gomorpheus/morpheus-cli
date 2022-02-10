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
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.list(params)
        return
      end
      json_response = @power_schedules_interface.list(params)
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
      title = "Morpheus Power Schedules"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if schedules.empty?
        print cyan,"No power schedules found.",reset,"\n"
      else
        print_schedules_table(schedules, options)
        print_results_pagination(json_response, {:label => "power schedule", :n_label => "power schedules"})
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
      @power_schedules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @power_schedules_interface.dry.get(schedule['id'])
        return
      end
      json_response = @power_schedules_interface.get(schedule['id'])
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

      print_h1 "Power Schedule Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        #"Account" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        "Type" => lambda {|it| format_schedule_type(it['scheduleType']) },
        "Enabled" => lambda {|it| format_boolean it['enabled'] },
        "Time Zone" => lambda {|it| it['scheduleTimezone'] || 'UTC (default)' },
        "Sunday" => lambda {|it| schedule_hour_to_time(it['sundayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['sundayOff'], it['unit']) },
        "Monday" => lambda {|it| schedule_hour_to_time(it['mondayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['mondayOff'], it['unit']) },
        "Tuesday" => lambda {|it| schedule_hour_to_time(it['tuesdayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['tuesdayOff'], it['unit']) },
        "Wednesday" => lambda {|it| schedule_hour_to_time(it['wednesdayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['wednesdayOff'], it['unit']) },
        "Thursday" => lambda {|it| schedule_hour_to_time(it['thursdayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['thursdayOff'], it['unit']) },
        "Friday" => lambda {|it| schedule_hour_to_time(it['fridayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['fridayOff'], it['unit']) },
        "Saturday" => lambda {|it| schedule_hour_to_time(it['saturdayOn'], it['unit']) + ' - ' + schedule_hour_to_time(it['saturdayOff'], it['unit']) },
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
    params = {'scheduleType' => 'power'}
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
      opts.on('--type [power|power off]', String, "Type of Schedule. Default is 'power'") do |val|
        params['scheduleType'] = val
      end
      opts.on('--timezone CODE', String, "The timezone. Default is UTC.") do |val|
        params['scheduleTimezone'] = val
      end
      [
        'sunday','monday','tuesday','wednesday','thursday','friday','saturday'
      ].each do |day|
        opts.on("--#{day}On 0-1440", String, "#{day.capitalize} start minute. Default is 0. Can be passed as HH:MM (24 hour) time format instead.") do |val|
          params["#{day}On"] = parse_time_to_minute(val)
        end
        opts.on("--#{day}Off 0-1440", String, "#{day.capitalize} end minute. Default is 1440. Can be passed as HH:MM (24 hour) time format instead.") do |val|
          params["#{day}Off"] = parse_time_to_minute(val)
        end
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
        params['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new power schedule." + "\n" +
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
      opts.on('--type [power|power off]', String, "Type of Schedule. Default is 'power'") do |val|
        params['scheduleType'] = val
      end
      opts.on('--timezone CODE', String, "The timezone. Default is UTC.") do |val|
        params['scheduleTimezone'] = val
      end
      [
        'sunday','monday','tuesday','wednesday','thursday','friday','saturday'
      ].each do |day|
        opts.on("--#{day}On 0-1440", String, "#{day.capitalize} start minute. Default is 0. Can be passed as HH:MM instead.") do |val|
          params["#{day}On"] = parse_time_to_minute(val)
        end
        opts.on("--#{day}Off 0-1440", String, "#{day.capitalize} end minute. Default is 1440. Can be passed as HH:MM instead.") do |val|
          params["#{day}Off"] = parse_time_to_minute(val)
        end
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
        params['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a power schedule." + "\n" +
                    "[name] is required. This is the name or id of a power schedule."
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

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete power schedule '#{schedule['name']}'?", options)
        return false
      end

      # payload = {
      #   'schedule' => {id: schedule["id"]}
      # }
      # payload['schedule'].merge!(schedule)
      payload = params
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
      opts.banner = subcommand_usage("[name] [instance]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Assign instances to a power schedule.\n" +
                    "[name] is required. This is the name or id of a power schedule.\n" +
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
      opts.footer = "Remove instances from a power schedule.\n" +
                    "[name] is required. This is the name or id of a power schedule.\n" +
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
      opts.footer = "Assign hosts to a power schedule.\n" +
                    "[name] is required. This is the name or id of a power schedule.\n" +
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
      opts.footer = "Remove hosts from a power schedule.\n" +
                    "[name] is required. This is the name or id of a power schedule.\n" +
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

  # convert the schedule on/off minute values [0-1440] to a time
  # older versions used hours 0-24 instead of minutes
  def schedule_hour_to_time(val, unit=nil, format=nil)
    hour = 0
    minute = 0
    if unit == 'minute'
      hour = (val.to_f / 60).floor
      minute = val.to_i % 60
    else
      hour = val.to_f.floor
      remainder = val.to_f % 1
      minute = remainder == 0 ? 0 : (60 * remainder).floor
    end
    # if hour > 23
    #   "Midnight" # "12:00 AM"
    # elsif hour > 12
    #   "#{(hour-12).to_s.rjust(2,'0')}:#{minute.to_s.rjust(2,'0')} PM"
    # else
    #   "#{hour.to_s.rjust(2,'0')}:#{minute.to_s.rjust(2,'0')} AM"
    # end
    if format == :short
      if minute == 0
        "#{hour}"
      else
        "#{hour}:#{minute.to_s.rjust(2,'0')}"
      end
    else
      "#{hour.to_s.rjust(2,'0')}:#{minute.to_s.rjust(2,'0')}"
    end
  end

  def format_schedule_days_short(schedule)
    [
      "Sn: #{schedule_hour_to_time(schedule['sundayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['sundayOff'], schedule['unit'], :short)}",
      "M: #{schedule_hour_to_time(schedule['mondayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['mondayOff'], schedule['unit'], :short)}",
      "T: #{schedule_hour_to_time(schedule['tuesdayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['tuesdayOff'], schedule['unit'], :short)}",
      "W: #{schedule_hour_to_time(schedule['wednesdayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['wednesdayOff'], schedule['unit'], :short)}",
      "Th: #{schedule_hour_to_time(schedule['thursdayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['thursdayOff'], schedule['unit'], :short)}",
      "F: #{schedule_hour_to_time(schedule['fridayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['fridayOff'], schedule['unit'], :short)}",
      "S: #{schedule_hour_to_time(schedule['saturdayOn'], schedule['unit'], :short)}-#{schedule_hour_to_time(schedule['saturdayOff'], schedule['unit'], :short)}",
    ].join(", ")
  end

  # parse a time in the format HH:MM to minutes 0-1440
  def parse_time_to_minute(val)
    m = 0
    # treat as minute 0-1440
    if val.to_s =~ /\A\d{1,}\Z/
      if val.to_i < 0 || val.to_i > 1440
        raise_command_error "Invalid minute value '#{val}', expected a value between 0 and 1440"
      else
        m = val.to_i
      end
    elsif val.to_s =~ /\A\d{1,2}\:\d{2}\Z/
      hour, minute = val.split(":")
      hour = hour.to_i
      minute = minute.to_i
      # allow 24:00 because this schedule data model is weird...
      if hour < 0 || hour > 24
        raise_command_error "Invalid time value '#{val}', expected format as HH:MM"
      elsif minute < 0 || minute > 59
        raise_command_error "Invalid time value '#{val}', expected format as HH:MM"
      end
      m = (hour * 60) + minute
    else
      raise_command_error "Invalid time value '#{val}', expected format as HH:MM"
    end
    return m
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
