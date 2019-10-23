require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/monitoring_helper'

class Morpheus::Cli::MonitoringChecksCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :'monitor-checks'
  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :mute, :unmute, :history #, :statistics
  register_subcommands :'mute-all' => :mute_all
  register_subcommands :'unmute-all' => :unmute_all
  register_subcommands :'list-types' => :list_types
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_interface = @api_client.monitoring
    @monitoring_checks_interface = @api_client.monitoring.checks
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      # todo: api to load type id by name
      # opts.on('--type VALUE', Array, "Filter by status. error,healthy,warning,muted") do |val|
      #   params['checkType'] = val
      # end
      opts.on('--status VALUE', Array, "Filter by status. error,healthy,warning,muted") do |val|
        params['status'] = val
      end
      build_common_options(opts, options, [:list, :query, :last_updated, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.list(params)
        return
      end
      json_response = @monitoring_checks_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "checks")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "checks")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['checks'], options)
        return 0
      end
      checks = json_response['checks']
      title = "Morpheus Monitoring Checks"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if checks.empty?
        print cyan,"No checks found.",reset,"\n"
      else
        print_checks_table(checks, options)
        print_results_pagination(json_response, {:label => "check", :n_label => "checks"})
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
      opts.on(nil,'--history', "Display Check History") do |val|
        options[:show_history] = true
      end
      # opts.on(nil,'--statistics', "Display Statistics") do |val|
      #   options[:show_statistics] = true
      # end
      build_common_options(opts, options, [:json, :csv, :fields, :dry_run, :remote])
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
      check = find_check_by_name_or_id(id)
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.get(check['id'])
        return
      end

      # get by ID to sideload associated checks
      json_response = @monitoring_checks_interface.get(check['id'])
      check = json_response['check']
      
      if options[:json]
        puts as_json(json_response, options, 'check')
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, 'check')
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['check']], options)
        return 0
      end

      print_h1 "Check Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Status" => lambda {|it| format_monitoring_check_status(it, true) },
        "Name" => lambda {|it| it['name'] },
        "Time" => lambda {|it| it['lastRunDate'] ? format_local_dt(it['lastRunDate']) : "N/A" },
        "Availability" => lambda {|it| it['availability'] ? "#{it['availability'].to_f.round(3).to_s}%" : "N/A"},
        "Response Time" => lambda {|it| it['lastTimer'] ? "#{it['lastTimer']}ms" : "N/A" },
        "Last Metric" => lambda {|it| 
          if it['lastMetric']
            metric_name = it['checkType'] ? it['checkType']['metricName'] : nil
            if metric_name
              "#{it['lastMetric']} #{metric_name}"
            else
              "#{it['lastMetric']}"
            end
          else
            "N/A" 
          end
        },
        "Type" => lambda {|it| format_monitoring_check_type(it) },
        "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : "System" },
        "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        # "Last Error" => lambda {|it| format_local_dt(it['lastErrorDate']) },
      }
      print_description_list(description_cols, check)

      # Last Error
      # if check['lastCheckStatus'] == 'error' && check['lastError']
      #   print_h2 "Last Error at #{format_local_dt(check['lastErrorDate'])}"
      #   print red,"#{check['lastError']}",reset,"\n"
      # end

      ## Chart Stats


      ## Activity

      ## Groups
      
      check_groups = json_response["groups"]
      if check_groups && !check_groups.empty?
        print_h2 "Check Groups"
        print as_pretty_table(check_groups, [:id, :name], options)
        #print_check_groups_table(check_groups, options)
      else
        # print "\n"
        # puts "This check is not in any check groups."
      end

      apps = json_response["apps"]
      if apps && apps.empty?
        print_h2 "Apps"
        print as_pretty_table(apps, [:id, :name], options)
      else
        # print "\n"
        # puts "This check is not in any monitoring apps."
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
        history_json_response = @monitoring_checks_interface.history(check["id"], {})
        history_items = history_json_response["history"] || history_json_response["events"]  || history_json_response["issues"]
        issues = history_items
        if history_items && !history_items.empty?
          print_h2 "History"
          print_check_history_table(history_items, options)
          print_results_pagination(history_json_response, {:label => "event", :n_label => "events"})
        else
          print "\n"
          puts "No history found for this check"
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
      check = find_check_by_name_or_id(args[0])
      # return false if check.nil?
      
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      # JD: lastUpdated 500ing, checks don't have that property ? =o  Fix it!
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.history(check['id'], params)
        return
      end

      json_response = @monitoring_checks_interface.history(check['id'], params)
      if options[:json]
        puts as_json(json_response, options, "history")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "history")
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['history'], options)
        return 0
      end
      history_items = json_response['history']
      title = "Check History: #{check['name']}"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
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
    options = {:skip_booleanize => true}
    params = {'inUptime' => true, 'severity' => 'critical'}
    check_type_code = nil
    check_type = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -t CODE")
      opts.on('-t', '--type CODE', "Check Type Code") do |val|
        check_type_code = val
      end
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--checkInterval MILLIS', String, "Check Interval. Value is in milliseconds. Default varies by type.") do |val|
        params['checkInterval'] = val.to_i # * 1000
      end
      opts.on('--severity VALUE', String, "Max Severity. Determines the maximum severity level this check can incur on an incident when failing. Default is critical") do |val|
        params['severity'] = val
      end
      opts.on('--inUptime [on|off]', String, "Affects Availability. Default is on.") do |val|
        params['inUptime'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('-c', '--config JSON', "Config settings as JSON") do |val|
        begin
          params['config'] = JSON.parse(val.to_s)
        rescue => ex
          raise ::OptionParser::InvalidOption.new("Failed to parse --config as JSON. Error: #{ex.message}")
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "List monitoring checks."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
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
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # merge in arbitrary option values
        if params['name'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'The name of this check.'}], options[:options])
          params['name'] = v_prompt['name']
        end

        # Check Type
        # rescue pre 3.6.5 error with maxResults.toLong()
        available_check_types = []
        begin
          available_check_types = @monitoring_checks_interface.list_check_types({max:1000})['checkTypes']
        rescue RestClient::Exception => e
          available_check_types = @monitoring_checks_interface.list_check_types({})['checkTypes']
        end
        if available_check_types && available_check_types.size > 0
          options[:options]['type'] = check_type_code if check_type_code
          check_types_dropdown = available_check_types.collect {|it| {'name' => it['name'], 'value' => it['code']} }
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'selectOptions' => check_types_dropdown, 'fieldLabel' => 'Check Type', 'required' => true, 'description' => 'The check type code.'}], options[:options])
          check_type_code = v_prompt['type']
        end
        if check_type_code
          params['checkType'] = {'code' => check_type_code}
        end

        # todo: load check type optionTypes and prompt accordingly..

        # include arbitrary -O options
        extra_passed_options = options[:options].reject {|k,v| k.is_a?(Symbol) || ['type'].include?(k)}
        params.deep_merge!(extra_passed_options)

        payload = {'check' => params}
      end
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.create(payload)
        return
      end
      json_response = @monitoring_checks_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        check = json_response['check']
        print_green_success "Added check #{check['name']}"
        _get(check['id'], options)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {:skip_booleanize => true}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--checkInterval VALUE', String, "Check Interval. Value is in milliseconds.") do |val|
        params['checkInterval'] = val.to_i # * 1000
      end
      opts.on('--severity VALUE', String, "Max Severity. Determines the maximum severity level this check can incur on an incident when failing. Default is critical") do |val|
        params['severity'] = val
      end
      opts.on('--inUptime [on|off]', String, "Affects Availability. Default is on.") do |val|
        params['inUptime'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update a monitoring check." + "\n" +
                    "[name] is required. This is the name or id of a check." + "\n" +
                    "The available options vary by type."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      check = find_check_by_name_or_id(args[0])
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
        payload = {'check' => params}
      end
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.update(check["id"], payload)
        return
      end
      json_response = @monitoring_checks_interface.update(check["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated check #{check['name']}"
        _get(check['id'], options)
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
      opts.on(nil, "--disable", "Disable mute state instead, the same as unmute") do
        params['enabled'] = false
        params['muted'] = false
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Mute a check. This prevents it from creating new incidents." + "\n" +
                    "[name] is required. This is the name or id of a check."
    end
    optparse.parse!(args)
    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      check = find_check_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.quarantine(check["id"], payload)
        return 0
      end
      json_response = @monitoring_checks_interface.quarantine(check["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if params['enabled']
          print_green_success "Muted check #{check['name']}"
        else
          print_green_success "Unmuted check #{check['name']}"
        end
        _get(check['id'], options)
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
      build_common_options(opts, options, [:payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Unmute a check." + "\n" +
                    "[name] is required. This is the name or id of a check."
    end
    optparse.parse!(args)
    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)

    begin
      check = find_check_by_name_or_id(args[0])
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = params
      end
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.quarantine(check["id"], payload)
        return 0
      end
      json_response = @monitoring_checks_interface.quarantine(check["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Unmuted check #{check['name']}"
        _get(check['id'], options)
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
      opts.on(nil, "--disable", "Disable mute state instead, the same as unmute-all") do
        params['muted'] = false
        params['enabled'] = false
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Mute all checks. This prevents the creation new incidents."
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
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.quarantine_all(payload)
        return 0
      end
      json_response = @monitoring_checks_interface.quarantine_all(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        num_updated = json_response['updated']
        if params['enabled']
          print_green_success "Muted #{num_updated} checks"
        else
          print_green_success "Unmuted #{num_updated} checks"
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
      build_common_options(opts, options, [:payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Unmute all checks."
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
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.quarantine_all(payload)
        return 0
      end
      json_response = @monitoring_checks_interface.quarantine_all(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        num_updated = json_response['updated']
        print_green_success "Unmuted #{num_updated} checks"
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
    if args.count != 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      check = find_check_by_name_or_id(args[0])

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete check '#{check['name']}'?", options)
        return false
      end
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.destroy(check["id"])
        return
      end

      json_response = @monitoring_checks_interface.destroy(check["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted check #{check['id']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_types(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List monitoring check types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @monitoring_checks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_checks_interface.dry.list_check_types(params)
        return
      end

      json_response = @monitoring_checks_interface.list_check_types(params)
      if options[:json]
        puts as_json(json_response, options, "checkTypes")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "checkTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["checkTypes"], options)
        return 0
      end
      check_types = json_response['checkTypes']
      title = "Check Types"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if check_types.empty?
        print cyan,"No check types found.",reset,"\n"
      else
        # columns = [:code, :name]
        columns = [
          # {"ID" => lambda {|check_type| check_type['id'] } },
          {"NAME" => lambda {|check_type| check_type['name'] } },
          {"CODE" => lambda {|check_type| check_type['code'] } },
          {"METRIC" => lambda {|check_type| check_type['metricName'] } },
          {"DEFAULT INTERVAL" => lambda {|check_type| check_type['defaultInterval'] ? format_human_duration(check_type['defaultInterval'].to_i / 1000) : '' } }
        ]
        print as_pretty_table(check_types, columns, options)
        print_results_pagination(json_response, {:label => "type", :n_label => "types"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private  

end
