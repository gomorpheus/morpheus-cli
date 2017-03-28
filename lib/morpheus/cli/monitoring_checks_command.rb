require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/monitoring_helper'

class Morpheus::Cli::MonitoringChecksCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :checks # :'monitoring-checks'
  register_subcommands :list, :get, :update, :remove, :quarantine, :history #, :statistics
  set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on('--status LIST', Array, "Filter by status. open, closed") do |list|
        params['status'] = list
      end
      opts.on('--severity LIST', Array, "Filter by severity. critical, warning, info") do |list|
        params['severity'] = list
      end
      build_common_options(opts, options, [:list, :last_updated, :json, :csv, :fields, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      # JD: lastUpdated 500ing, checks don't have that property ? =o  Fix it!

      if options[:dry_run]
        print_dry_run @monitoring_interface.checks.dry.list(params)
        return
      end

      json_response = @monitoring_interface.checks.list(params)
      if options[:json]
        if options[:include_fields]
          json_response = {"checks" => filter_data(json_response["checks"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['checks'], options)
        return 0
      end
      checks = json_response['checks']
      title = "Morpheus Checks"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
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
    optparse = OptionParser.new do|opts|
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

      if options[:dry_run]
        print_dry_run @monitoring_interface.checks.dry.get(check['id'])
        return
      end
      json_response = @monitoring_interface.checks.get(check['id'])
      check = json_response['check']
      
      if options[:json]
        if options[:include_fields]
          json_response = {"check" => filter_data(json_response["check"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['check']], options)
        return 0
      end

      print_h1 "Check Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Status" => lambda {|it| format_monitoring_check_status(it) },
        "Name" => lambda {|it| it['name'] },
        "Time" => lambda {|it| format_local_dt(it['lastRunDate']) },
        "Availability" => lambda {|it| it['availability'] ? "#{it['availability'].to_f.round(3).to_s}%" : "N/A"},
        "Response Time" => lambda {|it| it['lastTimer'] ? "#{it['lastTimer']}ms" : "N/A" },
        "Last Metric" => lambda {|it| it['lastMetric'] ? "#{it['lastMetric']}" : "N/A" },
        "Type" => 'checkType.name'
      }
      print_description_list(description_cols, check)

      ## Chart Stats


      ## Activity

      ## Groups
      
      check_groups = json_response["groups"]
      if check_groups && !check_groups.empty?
        print_h2 "Check Groups"
        print as_pretty_table(check_groups, [:id, {"Check Group" => :name}], options)
      else
        # print "\n"
        # puts "This check is not in any check groups."
      end

      ## Open Incidents

      open_incidents = json_response["openIncidents"]
      if open_incidents && !open_incidents.empty?
        print_h2 "Open Incidents"
        # puts "\n(table coming soon...)\n"
        puts print JSON.pretty_generate(open_incidents)
        # todo: move this to MonitoringHelper ?
        # print_incidents_table(issues, options)
      else
        print "\n"
        puts "No open incidents for this check"
      end

      ## History (plain old Hash)
      if options[:show_history]
        # history_items = json_response["history"]
        # gotta go get it
        history_json_response = @monitoring_interface.checks.history(check["id"], {})
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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id] [options]")
      # opts.on('--status LIST', Array, "Filter by status. open, closed") do |list|
      #   params['status'] = list
      # end
      opts.on('--severity LIST', Array, "Filter by severity. critical, warning, info") do |list|
        params['severity'] = list
      end
      build_common_options(opts, options, [:list, :last_updated, :json, :csv, :fields, :json, :dry_run])
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

      if options[:dry_run]
        print_dry_run @monitoring_interface.checks.dry.history(check['id'], params)
        return
      end

      json_response = @monitoring_interface.checks.history(check['id'], params)
      if options[:json]
        if options[:include_fields]
          json_response = {"history" => filter_data(json_response["history"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['history'], options)
        return 0
      end
      history_items = json_response['history']
      title = "Check History: #{check['id']}: #{check['displayName'] || check['name']}"
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

  def update(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      check = find_check_by_name_or_id(args[0])

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      payload = {
        'check' => {id: check["id"]}
      }
      payload['check'].merge!(params)

      if options[:dry_run]
        print_dry_run @monitoring_interface.checks.dry.update(check["id"], payload)
        return
      end

      json_response = @monitoring_interface.checks.update(check["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated check #{check['id']}"
        _get(check['id'], {})
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def quarantine(args)
    options = {}
    params = {'enabled' => true}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      # this one is a bit weird.. it's a way to toggle incident.inUptime
      # opts.on("--enabled BOOL", String, "Quarantine can be removed with --enabled false") do |val|
      #   params['enabled'] = ['on','true'].include?(val.to_s.downcase)
      # end
      opts.on("-d", "--disabled", "Disable Quarantine instead") do
        params['enabled'] = false
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      check = find_check_by_name_or_id(args[0])

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      # payload = {
      #   'check' => {id: check["id"]}
      # }
      # payload['check'].merge!(check)
      payload = params

      if options[:dry_run]
        print_dry_run @monitoring_interface.checks.dry.update(check["id"], payload)
        return
      end

      json_response = @monitoring_interface.checks.update(check["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Quarantined check #{check['id']}"
        _get(check['id'], {})
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      check = find_check_by_name_or_id(args[0])

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete check '#{check['name']}'?", options)
        return false
      end

      # payload = {
      #   'check' => {id: check["id"]}
      # }
      # payload['check'].merge!(check)
      payload = params

      if options[:dry_run]
        print_dry_run @monitoring_interface.checks.dry.destroy(check["id"])
        return
      end

      json_response = @monitoring_interface.checks.destroy(check["id"])
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


  private

  

end
