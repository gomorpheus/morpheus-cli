require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/monitoring_helper'

class Morpheus::Cli::MonitoringGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :'monitor-groups'
  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :mute, :unmute, :history #, :statistics
  register_subcommands :'mute-all' => :mute_all
  register_subcommands :'unmute-all' => :unmute_all
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).monitoring
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--status VALUE', Array, "Filter by status. error,healthy,warning,muted") do |val|
        params['status'] = val
      end
      build_common_options(opts, options, [:list, :last_updated, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))

      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.list(params)
        return
      end

      json_response = @monitoring_interface.groups.list(params)

      if options[:json]
        puts as_json(json_response, options, "checkGroups")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['checkGroups'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "checkGroups")
        return 0
      end
      check_groups = json_response['checkGroups']
      title = "Morpheus Monitoring Check Groups"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if check_groups.empty?
        print cyan,"No check groups found.",reset,"\n"
      else
        print_check_groups_table(check_groups, options)
        print_results_pagination(json_response, {:label => "check group", :n_label => "check groups"})
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
      opts.on(nil,'--history', "Display Check Group History") do |val|
        options[:show_history] = true
      end
      # opts.on(nil,'--statistics', "Display Statistics") do |val|
      #   options[:show_statistics] = true
      # end
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
      check_group = find_check_group_by_name_or_id(id)

      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.get(check_group['id'])
        return
      end
      json_response = @monitoring_interface.groups.get(check_group['id'])
      check_group = json_response['checkGroup']
      if options[:json]
        puts as_json(json_response, options, "checkGroup")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "checkGroup")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['checkGroup']], options)
        return 0
      end

      print_h1 "Check Group Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Status" => lambda {|it| format_monitoring_check_status(it, true) },
        "Name" => lambda {|it| it['name'] },
        "Time" => lambda {|it| format_local_dt(it['lastRunDate']) },
        "Availability" => lambda {|it| it['availability'] ? "#{it['availability'].to_f.round(3).to_s}%" : "N/A"},
        "Response Time" => lambda {|it| it['lastTimer'] ? "#{it['lastTimer']}ms" : "N/A" },
        # "Last Metric" => lambda {|it| it['lastMetric'] ? "#{it['lastMetric']}" : "N/A" },
        "Type" => lambda {|it| format_monitoring_check_type(it) },
      }
      print_description_list(description_cols, check_group)

      ## Chart Stats


      ## Activity

      ## Checks in this check group
      checks = json_response["checks"]
      if checks && !checks.empty?
        print_h2 "Checks"
        # print as_pretty_table(check_groups, [:id, {"Check Group" => :name}], options)
        print_checks_table(checks, options)
      else
        # print "\n"
        # puts "No checks found..."
      end

      ## Open Incidents

      open_incidents = json_response["openIncidents"]
      if open_incidents && !open_incidents.empty?
        print_h2 "Open Incidents"
        # puts "\n(table coming soon...)\n"
        puts JSON.pretty_generate(open_incidents)
        # todo: move this to MonitoringHelper ?
        # print_incidents_table(issues, options)
      else
        print "\n", cyan
        puts "No open incidents for this check group"
      end

      ## History (plain old Hash)
      if options[:show_history]
        # history_items = json_response["history"]
        # gotta go get it
        history_json_response = @monitoring_interface.groups.history(check_group["id"], {})
        history_items = history_json_response["history"] || history_json_response["events"]  || history_json_response["issues"]
        issues = history_items
        if history_items && !history_items.empty?
          print_h2 "History"
          print_check_history_table(history_items, options)
          print_results_pagination(history_json_response, {:label => "event", :n_label => "events"})
        else
          print "\n"
          puts "No history found for this check group"
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
      check_group = find_check_group_by_name_or_id(args[0])
      return 1 if check_group.nil?
      
      # construct payload
      params.merge!(parse_list_options(options))

      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.history(check_group['id'], params)
        return
      end

      json_response = @monitoring_interface.groups.history(check_group['id'], params)
      if options[:json]
        puts as_json(json_response, options, "history")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["history"], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "history")
        return 0
      end
      history_items = json_response["history"]
      title = "Check Group History - [#{check_group['id']}] #{check_group['displayName'] || check_group['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if history_items.empty?
        print cyan,"No history found.",reset,"\n"
      else
        print_check_history_table(history_items, options)
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
      opts.on('--minHappy VALUE', String, "Min Checks. This specifies the minimum number of checks within the group that must be happy to keep the group from becoming unhealthy.") do |val|
        params['minHappy'] = val.to_i
      end
      opts.on('--severity VALUE', String, "Max Severity. Determines the maximum severity level this group can incur on an incident when failing. Default is critical") do |val|
        params['severity'] = val
      end
      opts.on('--inUptime [on|off]', String, "Affects Availability. Default is on.") do |val|
        params['inUptime'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--checks LIST', Array, "Checks to include in this group, comma separated list of IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          params['checks'] = []
        else
          params['checks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new group of monitoring checks." + "\n" +
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
        if params['checks']
          params['checks'] = params['checks'].collect {|it| it.to_i }
        end
        # todo: prompt?
        payload = {'checkGroup' => params}
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.create(payload)
        return
      end
      json_response = @monitoring_interface.groups.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        check_group = json_response['checkGroup']
        print_green_success "Added check group #{check_group['name']}"
        _get(check_group['id'], {})
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
      opts.on('--name VALUE', String, "Name for this check group") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--minHappy VALUE', String, "Min Checks. This specifies the minimum number of checks within the group that must be happy to keep the group from becoming unhealthy.") do |val|
        params['minHappy'] = val.to_i
      end
      opts.on('--severity VALUE', String, "Max Severity. Determines the maximum severity level this group can incur on an incident when failing. Default is critical") do |val|
        params['severity'] = val
      end
      opts.on('--inUptime [on|off]', String, "Affects Availability. Default is on.") do |val|
        params['inUptime'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--checks LIST', Array, "Checks to include in this group, comma separated list of IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          params['checks'] = []
        else
          params['checks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a check group." + "\n" +
                    "[name] is required. This is the name or id of a check group."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      check_group = find_check_group_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        if params['checks']
          params['checks'] = params['checks'].collect {|it| it.to_i }
        end
        # todo: prompt?
        payload = {'checkGroup' => params}
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.update(check_group["id"], payload)
        return
      end
      json_response = @monitoring_interface.groups.update(check_group["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated check group #{check_group['name']}"
        _get(check_group['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def mute(args)
    options = {}
    params = {'enabled' => true}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on(nil, "--disable", "Disable mute, the same as unmute") do
        params['enabled'] = false
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Mute a check group. This prevents it from creating new incidents." + "\n" +
                    "[name] is required. This is the name or id of a check group."
    end
    optparse.parse!(args)
    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      check_group = find_check_group_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.quarantine(check_group["id"], payload)
        return 0
      end
      json_response = @monitoring_interface.groups.quarantine(check_group["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if params['enabled']
          print_green_success "Muted group #{check_group['name']}"
        else
          print_green_success "Unmuted group #{check_group['name']}"
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
    params = {'enabled' => false}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Unmute a check group." + "\n" +
                    "[name] is required. This is the name or id of a check."
    end
    optparse.parse!(args)
    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)

    begin
      check_group = find_check_group_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.quarantine(check_group["id"], payload)
        return 0
      end
      json_response = @monitoring_interface.groups.quarantine(check_group["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Unmuted group #{check_group['name']}"
        _get(check_group['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def mute_all(args)
    options = {}
    params = {'enabled' => true}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on(nil, "--disable", "Disable mute, the same as unmute-all") do
        params['enabled'] = false
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Mute all check groups. This prevents the creation of new incidents."
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
      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.quarantine_all(payload)
        return 0
      end
      json_response = @monitoring_interface.groups.quarantine_all(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        num_updated = json_response['updated']
        if params['enabled']
          print_green_success "Muted #{num_updated} check groups"
        else
          print_green_success "Unmuted #{num_updated} check groups"
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
    params = {'enabled' => false}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Unmute all check groups."
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
      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.quarantine_all(payload)
        return 0
      end
      json_response = @monitoring_interface.groups.quarantine_all(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        num_updated = json_response['updated']
        print_green_success "Unmuted #{num_updated} check groups"
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
      build_common_options(opts, options, [:json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      check_group = find_check_group_by_name_or_id(args[0])

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete check group '#{check_group['name']}'?", options)
        return false
      end

      # payload = {
      #   'checkGroup' => {id: check_group["id"]}
      # }
      # payload['checkGroup'].merge!(check_group)
      payload = params

      if options[:dry_run]
        print_dry_run @monitoring_interface.groups.dry.destroy(check_group["id"])
        return
      end

      json_response = @monitoring_interface.groups.destroy(check_group["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted check group #{check_group['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

end
