require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/monitoring_helper'

class Morpheus::Cli::MonitoringIncidentsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :incidents  # :'monitoring-incidents'
  register_subcommands :list, :stats, :get, :history, :notifications, :update, :close, :reopen, :quarantine
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
      # JD: lastUpdated 500ing, incidents don't have that property ? =o  Fix it!

      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.list(params)
        return
      end

      json_response = @monitoring_interface.incidents.list(params)
      if options[:json]
        if options[:include_fields]
          json_response = {"incidents" => filter_data(json_response["incidents"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['incidents'], options)
        return 0
      end
      incidents = json_response['incidents']
      title = "Morpheus Incidents"
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
      if incidents.empty?
        print cyan,"No incidents found.",reset,"\n"
      else
        print_incidents_table(incidents, options)
        print_results_pagination(json_response, {:label => "incident", :n_label => "incidents"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # this show date range counts and current open incidents
  # it should be perhaps called 'summary' or 'dashboard'
  # it is not stats about a particular incident
  def stats(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      #opts.on('-j','--json', "JSON Output") do
      opts.on( '-m', '--max MAX', "Max open incidents to display. Default is 25" ) do |max|
        if max.to_s == 'all'
          options[:max] = 10000 # 'all'
        else
          options[:max] = max.to_i
        end
      end
      opts.on( '-o', '--offset OFFSET', "Offset open incidents results for pagination." ) do |offset|
        options[:offset] = offset.to_i.abs
      end
      build_common_options(opts, options, [:json, :fields, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.stats(params)
        return
      end
      json_response = @monitoring_interface.incidents.stats(params)
      if options[:json]
        if options[:include_fields]
          json_response.merge!({"openIncidents" => filter_data(json_response["openIncidents"], options[:include_fields])})
        end
        puts as_json(json_response, options)
        return 0
      end
      # if options[:csv]
      #   puts records_as_csv(json_response['openIncidents'], options)
      #   return 0
      # end
      open_incidents = json_response['openIncidents']
      open_incidents_count = json_response['openIncidentCount']
      stats = json_response['incidentStats']

      print_h1 "Morpheus Incidents: Stats"
      print cyan

      # print_h2 "Counts"
      # print_description_list({
      #   "Today" => 'today',
      #   "Week" => 'week',
      #   "Month" => 'month',
      # }, stats)

      if stats
        print justify_string("Today: #{stats['today']}", 20)
        print justify_string("Week: #{stats['week']}", 20)
        print justify_string("Month: #{stats['month']}", 20)
        print "\n"
      else
        puts "No stats"
      end

      if !open_incidents || open_incidents.size() == 0
        print bold,green,"0 open incidents",reset,"\n"
      else
        if open_incidents.size() == 1
          #print bold,yellow,"#{open_incidents.size()} open incident",reset,"\n"
          print_h2 "#{open_incidents.size()} open incident"
        else
          #print bold,yellow,"#{open_incidents.size()} open incidents",reset,"\n"
          print_h2 "#{open_incidents.size()} open incidents"
        end
        options[:max] ||= 20
        
        print_incidents_table(open_incidents)
        if open_incidents.size > 0
          print_results_pagination(size: open_incidents.size, total: open_incidents_count, offset: options[:offset])
        end
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
      opts.on(nil,'--history', "Display Incident History") do |val|
        options[:show_history] = true
      end
      opts.on(nil,'--notifications', "Display Incident Notifications") do |val|
        options[:show_notifications] = true
      end
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
      incident = find_incident_by_id(id)
      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.get(incident['id'])
        return
      end
      json_response = @monitoring_interface.incidents.get(incident['id'])
      incident = json_response['incident']
      
      if options[:json]
        if options[:include_fields]
          json_response = {"incident" => filter_data(json_response["incident"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['incident']], options)
        return 0
      end

      print_h1 "Incident Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Severity" => lambda {|it| format_severity(it['severity']) },
        "Name" => lambda {|it| it['displayName'] || it['name'] || 'No Subject' },
        "Start" => lambda {|it| format_local_dt(it['startDate']) },
        "End" => lambda {|it| format_local_dt(it['endDate']) },
        "Duration" => lambda {|it| format_duration(it['startDate'], it['endDate']) },
        "Status" => lambda {|it| format_monitoring_issue_status(it) },
        "Visibility" => 'visibility',
        "Last Check" => lambda {|it| format_local_dt(it['lastCheckTime']) },
        "Last Error" => lambda {|it| it['lastError'] },
        "Comment" => 'comment',
        "Resolution" => 'resolution'
      }
      # description_cols.delete("End") if incident['endDate'].nil?
      description_cols.delete("Comment") if incident['comment'].empty?
      description_cols.delete("Resolution") if incident['resolution'].empty?
      # description_cols.delete("Last Check") if incident['lastCheckTime'].empty?
      # description_cols.delete("Last Error") if incident['lastError'].empty?
      print_description_list(description_cols, incident)
      # puts as_vertical_table(incident, description_cols)
      ## Issues

      issues = json_response["issues"]
      if issues && !issues.empty?
        print_h2 "Issues"
        print_incident_history_table(issues, options)
      else
        print "\n"
        puts "No checks involved in this incident"
      end

      ## History (MonitorIncidentEvent)
      if options[:show_history]
        # history_items = json_response["history"]
        # gotta go get it
        history_json_response = @monitoring_interface.incidents.history(incident["id"], {})
        history_items = history_json_response["history"] || history_json_response["events"]  || history_json_response["issues"]
        issues = history_items
        if history_items && !history_items.empty?
          print_h2 "History"
          print_incident_history_table(history_items, options)
          print_results_pagination(history_json_response, {:label => "event", :n_label => "events"})
        else
          print "\n"
          puts "No history found for this incident"
        end
      end

      ## Members (MonitorIncidentNotifyEvent)
      if options[:show_notifications]
        # history_items = json_response["history"]
        # gotta go get it
        notifications_json_response = @monitoring_interface.incidents.notifications(incident["id"], {max: 10})
        notification_items = notifications_json_response["notifications"]
        if notification_items && notification_items.empty?
          print_h2 "Notifications"
          print_incident_notifications_table(notification_items, options)
          print_results_pagination(notifications_json_response, {:label => "notification", :n_label => "notifications"})
        else
          print "\n"
          puts "Nobody has been notified about this incident."
        end
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
      incident = find_incident_by_id(args[0])
      # return false if incident.nil?
      
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      # JD: lastUpdated 500ing, incidents don't have that property ? =o  Fix it!

      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.history(incident['id'], params)
        return
      end

      json_response = @monitoring_interface.incidents.history(incident['id'], params)
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
      title = "Incident History: #{incident['id']}: #{incident['displayName'] || incident['name']}"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if history_items.empty?
        print cyan,"No history found.",reset,"\n"
      else
        print_incident_history_table(history_items, options)
        print_results_pagination(json_response, {:label => "event", :n_label => "events"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def notifications(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id] [options]")
      build_common_options(opts, options, [:list, :json, :csv, :fields, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      incident = find_incident_by_id(args[0])
      # return false if incident.nil?
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      
      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.notifications(incident['id'], params)
        return
      end

      json_response = @monitoring_interface.incidents.notifications(incident['id'], params)
      if options[:json]
        if options[:include_fields]
          json_response = {"notifications" => filter_data(json_response["notifications"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['notifications'], options)
        return 0
      end
      notification_items = json_response['notifications']
      title = "Incident Notifications: #{incident['id']}: #{incident['displayName'] || incident['name']}"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if notification_items.empty?
        print cyan,"No notifications found.",reset,"\n"
      else
        print_incident_history_table(notification_items, options)
        print_results_pagination(json_response, {:label => "notification", :n_label => "notifications"})
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
      opts.on("-c", "--comment STRING", String, "Comment on this incident") do |val|
        params['comment'] = val == 'null' ? nil : val
      end
      opts.on("--resolution STRING", String, "Description of the resolution to this incident") do |val|
        params['resolution'] = val == 'null' ? nil : val
      end
      opts.on("--status STATUS", String, "Set status (open or closed)") do |val|
        params['status'] = val
      end
      opts.on("--severity STATUS", String, "Set severity (critical, warning or info)") do |val|
        params['severity'] = val
      end
      opts.on("--name STRING", String, "Set display name (subject)") do |val|
        params['name'] = val == 'null' ? nil : val
      end
      opts.on("--startDate TIME", String, "Set start time") do |val|
        begin
          params['startDate'] = parse_time(val).utc.iso8601
        rescue => e
          raise OptionParser::InvalidArgument.new "Failed to parse --startDate '#{val}'. Error: #{e}"
        end
      end
      opts.on("--endDate TIME", String, "Set end time") do |val|
        begin
          params['endDate'] = parse_time(val).utc.iso8601
        rescue => e
          raise OptionParser::InvalidArgument.new "Failed to parse --endDate '#{val}'. Error: #{e}"
        end
      end
      opts.on("--inUptime BOOL", String, "Set 'In Availability'") do |val|
        params['inUptime'] = ['true','on'].include?(val.to_s.strip)
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      incident = find_incident_by_id(args[0])

      if params['status'] == 'closed'
        unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to close the incident '#{incident['id']}'?", options)
          return false
        end
      end

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      payload = {
        'incident' => {id: incident["id"]}
      }
      payload['incident'].merge!(params)

      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.update(incident["id"], payload)
        return
      end

      json_response = @monitoring_interface.incidents.update(incident["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated incident #{incident['id']}"
        _get(incident['id'], {})
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
      incident = find_incident_by_id(args[0])

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      # payload = {
      #   'incident' => {id: incident["id"]}
      # }
      # payload['incident'].merge!(params)
      payload = params

      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.update(incident["id"], payload)
        return
      end

      json_response = @monitoring_interface.incidents.update(incident["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Quarantined incident #{incident['id']}"
        _get(incident['id'], {})
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def close(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to close #{id_list.size == 1 ? 'incident' : 'incidents'} #{anded_list(id_list)}?", options)
      exit 1
    end
    return run_command_for_each_arg(id_list) do |arg|
      _close(arg, options)
    end
  end

  def _close(id, options)

    begin
      incident = find_incident_by_id(id)
      already_closed = incident['status'] == 'closed'
      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.close(incident['id'])
        return
      end
      json_response = @monitoring_interface.incidents.close(incident['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success json_response["msg"] || "Incident #{incident['id']} is now closed"
        # _get(incident['id'] {})
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def reopen(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to reopen #{id_list.size == 1 ? 'incident' : 'incidents'} #{anded_list(id_list)}?", options)
      exit 1
    end
    return run_command_for_each_arg(id_list) do |arg|
      _reopen(arg, options)
    end
  end

  def _reopen(id, options)

    begin
      incident = find_incident_by_id(id)
      already_open = incident['status'] == 'open'
      if already_open
        print bold,yellow,"Incident #{incident['id']} is already open",reset,"\n"
        return false
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.incidents.dry.reopen(incident['id'])
        return
      end
      json_response = @monitoring_interface.incidents.reopen(incident['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success json_response["msg"] || "Incident #{incident['id']} is now open"
        # _get(incident['id'] {})
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def print_incidents_table(incidents, opts={})
    columns = [
      {"ID" => lambda {|incident| incident['id'] } },
      {"SEVERITY" => lambda {|incident| format_severity(incident['severity']) } },
      {"NAME" => lambda {|incident| incident['displayName'] || incident['name'] || 'No Subject' } },
      {"TIME" => lambda {|incident| format_local_dt(incident['startDate']) } },
      {"STATUS" => lambda {|incident| format_monitoring_incident_status(incident) } },
      {"DURATION" => lambda {|incident| format_duration(incident['startDate'], incident['endDate']) } }
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(incidents, columns, opts)
  end

  def print_incident_history_table(history_items, opts={})
    columns = [
      # {"ID" => lambda {|issue| issue['id'] } },
      {"SEVERITY" => lambda {|issue| format_severity(issue['severity']) } },
      {"AVAILABLE" => lambda {|issue| format_boolean issue['available'] } },
      {"TYPE" => lambda {|issue| issue["attachmentType"] } },
      {"NAME" => lambda {|issue| issue['name'] } },
      {"DATE CREATED" => lambda {|issue| format_local_dt(issue['startDate']) } }
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(history_items, columns, opts)
  end

  def print_incident_notifications_table(notifications, opts={})
    columns = [
      {"NAME" => lambda {|notification| notification['recipient'] ? notification['recipient']['name'] : '' } },
      {"DELIVERY TYPE" => lambda {|notification| notification['addressTypes'].to_s } },
      {"NOTIFIED ON" => lambda {|notification| format_local_dt(notification['dateCreated']) } },
      # {"AVAILABLE" => lambda {|notification| format_boolean notification['available'] } },
      # {"TYPE" => lambda {|notification| notification["attachmentType"] } },
      # {"NAME" => lambda {|notification| notification['name'] } },
      {"DATE CREATED" => lambda {|notification| 
        date_str = format_local_dt(notification['startDate']).to_s
        if notification['pendingUtil']
          "(pending) #{date_str}"
        else
          date_str
        end
      } }
    ]
    #event['pendingUntil']
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(notifications, columns, opts)
  end

end
