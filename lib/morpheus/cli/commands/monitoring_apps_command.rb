require 'morpheus/cli/cli_command'

class Morpheus::Cli::MonitoringAppsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :'monitor-apps'

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :mute, :unmute
  register_subcommands :'mute-all' => :mute_all
  register_subcommands :'unmute-all' => :unmute_all
  #register_subcommands :history

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_interface = @api_client.monitoring
    @monitoring_apps_interface = @api_client.monitoring.apps
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--status LIST', Array, "Filter by status. error,healthy,warning,muted") do |list|
        params['status'] = list
      end
      build_common_options(opts, options, [:list, :query, :last_updated, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.list(params)
        return
      end

      json_response = @monitoring_apps_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "monitorApps")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['monitorApps'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "monitorApps")
        return 0
      end
      monitor_apps = json_response['monitorApps']
      title = "Morpheus Monitoring Apps"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if monitor_apps.empty?
        print cyan,"No monitoring apps found.",reset,"\n"
      else
        print_monitoring_apps_table(monitor_apps, options)
        print_results_pagination(json_response, {:label => "monitoring app", :n_label => "monitoring apps"})
        # print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
  
  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      opts.on(nil,'--history', "Display Monitoring App History") do |val|
        options[:show_history] = true
      end
      # opts.on(nil,'--statistics', "Display Statistics") do |val|
      #   options[:show_statistics] = true
      # end
      opts.on('-a','--all', "Display All Details (History, Notifications)") do
        options[:show_history] = true
        options[:show_notifications] = true
        options[:show_statistics] = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)

    begin
      monitor_app = find_monitoring_app_by_name_or_id(id)
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.get(monitor_app['id'])
        return
      end
      # get by ID to sideload associated checks
      json_response = @monitoring_apps_interface.get(monitor_app['id'])
      monitor_app = json_response['monitorApp']
      if options[:json]
        puts as_json(json_response, options, "monitorApp")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "monitorApp")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['monitorApp']], options)
        return 0
      end

      print_h1 "Monitoring App Details", [], options
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Status" => lambda {|it| format_monitoring_check_status(it, true) },
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        "Time" => lambda {|it| format_local_dt(it['lastRunDate']) },
        "Availability" => lambda {|it| it['availability'] ? "#{it['availability'].to_f.round(3).to_s}%" : "N/A"},
        "Response Time" => lambda {|it| it['lastTimer'] ? "#{it['lastTimer']}ms" : "N/A" }
      }
      print_description_list(description_cols, monitor_app, options)

      ## Chart Stats


      ## Checks in this app
      checks = json_response["checks"]
      if checks && !checks.empty?
        print_h2 "Checks", options
        print_checks_table(checks, options)
      else
        # print "\n"
        # puts "No checks in this monitoring app"
      end

      ## Check Groups in this app
      check_groups = json_response["checkGroups"]
      if check_groups && !check_groups.empty?
        print_h2 "Groups", options
        print_check_groups_table(check_groups, options)
      else
        # print "\n"
        # puts "No check groups in this monitoring app"
      end

      ## Checks in this check group
      if (!checks || checks.empty?) && (check_groups || check_groups.empty?)
        print "\n", yellow
        puts "This monitor app is empty, it contains no checks or groups."
      end

      ## Open Incidents
      open_incidents = json_response["openIncidents"]
      if open_incidents && !open_incidents.empty?
        print_h2 "Open Incidents"
        print_incidents_table(open_incidents)
        # print_results_pagination(size: open_incidents.size, total: open_incidents.size)
      else
        print "\n", cyan
        puts "No open incidents for this monitoring app"
      end

      ## History (plain old Hash)
      if options[:show_history]
        # history_items = json_response["history"]
        # gotta go get it
        history_json_response = @monitoring_apps_interface.history(monitor_app["id"], {})
        history_items = history_json_response["history"] || history_json_response["events"]  || history_json_response["issues"]
        issues = history_items
        if history_items && !history_items.empty?
          print_h2 "History"
          print_monitor_app_history_table(history_items, options)
          print_results_pagination(history_json_response, {:label => "event", :n_label => "events"})
        else
          print "\n"
          puts "No history found for this monitoring app"
        end
      end

      ## Statistics (Hash)
      if options[:show_statistics]
        # todo....
      end

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      # opts.on('--status LIST', Array, "Filter by status. open, closed") do |list|
      #   params['status'] = list
      # end
      opts.on('--severity LIST', Array, "Filter by severity. critical, warning, info") do |list|
        params['severity'] = list
      end
      build_common_options(opts, options, [:list, :last_updated, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      monitor_app = find_monitoring_app_by_name_or_id(args[0])
      return 1 if monitor_app.nil?
      
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      # JD: lastUpdated 500ing, checks don't have that property ? =o  Fix it!
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.history(monitor_app['id'], params)
        return
      end

      json_response = @monitoring_apps_interface.history(monitor_app['id'], params)
      if options[:json]
        puts as_json(json_response, options, "history")
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['history'], options)
        return 0
      end
      history_items = json_response['history']
      title = "Monitoring App History: #{monitor_app['name']}"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if history_items.empty?
        print cyan,"No history found.",reset,"\n"
      else
        print_monitor_app_history_table(history_items, options)
        print_results_pagination(json_response, {:label => "event", :n_label => "events"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {'inUptime' => true, 'severity' => 'critical'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--minHappy VALUE', String, "Min Checks. This specifies the minimum number of checks within the app that must be happy to keep the app from becoming unhealthy.") do |val|
        params['minHappy'] = val.to_i
      end
      opts.on('--severity VALUE', String, "Max Severity. Determines the maximum severity level this app can incur on an incident when failing. Default is critical") do |val|
        params['severity'] = val
      end
      opts.on('--inUptime [on|off]', String, "Affects Availability. Default is on.") do |val|
        params['inUptime'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muted [on|off]', String, "Muted, Turns Affects Availability off.") do |val|
        params['muted'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--checks LIST', Array, "Checks to include in this app, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checks'] = []
        else
          params['checks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--groups LIST', Array, "Check Groups to include in this app, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checkGroups'] = []
        else
          params['checkGroups'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new app of monitoring checks." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
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
        if params['name'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'The name of this alert rule.'}], options[:options])
          params['name'] = v_prompt['name']
        end
        if params['severity'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'severity', 'type' => 'text', 'fieldLabel' => 'Severity', 'required' => false, 'description' => 'Max Severity. Determines the maximum severity level this app can incur on an incident when failing. Default is critical', 'defaultValue' => 'critical'}], options[:options])
          params['severity'] = v_prompt['severity'] unless v_prompt['severity'].to_s.empty?
        end
        if params['inUptime'].nil? && params['muted'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'inUptime', 'type' => 'checkbox', 'fieldLabel' => 'Affects Availability', 'required' => false, 'description' => 'Affects Availability. Default is on.', 'defaultValue' => true}], options[:options])
          params['inUptime'] = v_prompt['inUptime'] unless v_prompt['inUptime'].to_s.empty?
        end

        # Checks
        prompt_results = prompt_for_checks(params, options, @api_client)
        if prompt_results[:success]
          params['checks'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1
        end

        # Check Groups
        prompt_results = prompt_for_check_groups(params, options, @api_client)
        if prompt_results[:success]
          params['checkGroups'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1
        end

        payload = {'monitorApp' => params}
      end
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.create(payload)
        return
      end
      json_response = @monitoring_apps_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        monitor_app = json_response['monitorApp']
        print_green_success "Added monitoring app #{monitor_app['name']}"
        _get(monitor_app['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
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
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--minHappy VALUE', String, "Min Checks. This specifies the minimum number of checks within the app that must be happy to keep the app from becoming unhealthy.") do |val|
        params['minHappy'] = val.to_i
      end
      opts.on('--severity VALUE', String, "Max Severity. Determines the maximum severity level this app can incur on an incident when failing. Default is critical") do |val|
        params['severity'] = val
      end
      opts.on('--inUptime [on|off]', String, "Affects Availability. Default is on.") do |val|
        params['inUptime'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muted [on|off]', String, "Muted, Turns Affects Availability off.") do |val|
        params['muted'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--checks LIST', Array, "Checks to include in this app, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checks'] = []
        else
          params['checks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--groups LIST', Array, "Check Groups to include in this app, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checkGroups'] = []
        else
          params['checkGroups'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a monitoring app." + "\n" +
                    "[name] is required. This is the name or id of a monitoring app."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      monitor_app = find_monitoring_app_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Checks
        if params['checks']
          prompt_results = prompt_results(params, options, @api_client)
          if prompt_results[:success]
            params['checks'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1
          end
        end

        # Check Groups
        if params['checkGroups']
          prompt_results = prompt_for_check_groups(params, options, @api_client)
          if prompt_results[:success]
            params['checkGroups'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1
          end
        end

        payload = {'monitorApp' => params}
      end
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.update(monitor_app["id"], payload)
        return
      end
      json_response = @monitoring_apps_interface.update(monitor_app["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated monitoring app #{monitor_app['name']}"
        _get(monitor_app['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def mute(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on(nil, "--disable", "Unmute instead, the same as the unmute command") do
        params['muted'] = false
        params['enabled'] = false
      end
      opts.footer = "Mute a monitoring app. This prevents it from creating new incidents." + "\n" +
                    "[name] is required. This is the name or id of a monitoring app."
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      monitor_app = find_monitoring_app_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.quarantine(monitor_app["id"], payload)
        return 0
      end
      json_response = @monitoring_apps_interface.quarantine(monitor_app["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if params['muted'] != false
          print_green_success "Muted app #{monitor_app['name']}"
        else
          print_green_success "Unmuted app #{monitor_app['name']}"
        end
        _get(monitor_app['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def unmute(args)
    options = {}
    params = {'muted' => false, 'enabled' => false}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Unmute a monitoring app." + "\n" +
                    "[name] is required. This is the name or id of a monitoring app."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      monitor_app = find_monitoring_app_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.quarantine(monitor_app["id"], payload)
        return 0
      end
      json_response = @monitoring_apps_interface.quarantine(monitor_app["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Unmuted app #{monitor_app['name']}"
        _get(monitor_app['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def mute_all(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on(nil, "--disable", "Unmute instead, the same as the unmute-all command") do
        params['muted'] = false
        params['enabled'] = false
      end
      opts.footer = "Mute all monitoring apps. This prevents the creation of new incidents."
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count != 0
      puts optparse
      return 1
    end
    connect(options)
    begin
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.quarantine_all(payload)
        return 0
      end
      json_response = @monitoring_apps_interface.quarantine_all(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        num_updated = json_response['updated']
        if params['muted'] != false
          print_green_success "Muted #{num_updated} apps"
        else
          print_green_success "Unmuted #{num_updated} apps"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def unmute_all(args)
    options = {}
    params = {'muted' => false, 'enabled' => false}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Unmute all monitoring apps."
    end
    optparse.parse!(args)
    if args.count != 0
      puts optparse
      return 1
    end
    connect(options)

    begin
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.quarantine_all(payload)
        return 0
      end
      json_response = @monitoring_apps_interface.quarantine_all(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        num_updated = json_response['updated']
        print_green_success "Unmuted #{num_updated} apps"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      monitor_app = find_monitoring_app_by_name_or_id(args[0])

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete monitoring app '#{monitor_app['name']}'?", options)
        return false
      end

      # payload = {
      #   'monitorApp' => {id: monitor_app["id"]}
      # }
      # payload['monitorApp'].merge!(monitor_app)
      payload = params
      @monitoring_apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_apps_interface.dry.destroy(monitor_app["id"])
        return
      end

      json_response = @monitoring_apps_interface.destroy(monitor_app["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted check app #{monitor_app['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

end
