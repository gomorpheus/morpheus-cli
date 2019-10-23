# require 'yaml'
require 'time'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::MonitoringAlertsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :'monitor-alerts'

  register_subcommands :list, :get, :add, :update, :remove
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_interface = @api_client.monitoring
    @monitoring_alerts_interface = @api_client.monitoring.alerts
    @monitoring_checks_interface = @api_client.monitoring.checks
    @monitoring_groups_interface = @api_client.monitoring.groups
    @monitoring_apps_interface = @api_client.monitoring.apps
    @monitoring_contacts_interface = @api_client.monitoring.contacts
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :csv, :yaml, :fields, :json, :dry_run, :remote])
      opts.footer = "List monitoring alert rules."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      # JD: lastUpdated 500ing, alerts don't have that property ? =o  Fix it!
      @monitoring_alerts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_alerts_interface.dry.list(params)
        return
      end

      json_response = @monitoring_alerts_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "alerts")
        return 0
      elsif options[:yaml]
        puts as_json(json_response, options, "alerts")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['alerts'], options)
        return 0
      end
      alerts = json_response['alerts']
      title = "Morpheus Monitoring Alerts"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if alerts.empty?
        print cyan,"No alerts found.",reset,"\n"
      else
        print_alerts_table(alerts, options)
        print_results_pagination(json_response, {:label => "alert", :n_label => "alerts"})
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
      opts.banner = subcommand_usage("[alert]")
      opts.on(nil,'--history', "Display History") do |val|
        options[:show_history] = true
      end
      opts.on(nil,'--notifications', "Display Notifications") do |val|
        options[:show_notifications] = true
      end
      build_common_options(opts, options, [:json, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a monitoring alert rule." + "\n" +
                    "[alert] is required. This is the name or ID of the alert rule. Supports 1-N [alert] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)

    begin
      alert = find_alert_by_name_or_id(id)
      @monitoring_alerts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_alerts_interface.dry.get(alert['id'])
        return
      end
      # get by ID to sideload associated checks,groups,apps
      json_response = @monitoring_alerts_interface.get(alert['id'])
      alert = json_response['alert']
      if options[:json]
        puts as_json(json_response, options, "alert")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "alert")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['alert']], options)
        return 0
      end

      print_h1 "Alert Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Min. Severity" => "minSeverity",
        "Min. Duration" => lambda {|alert| alert['minDuration'] && alert['minDuration'].to_i > 0 ? "#{alert['minDuration']} minutes" : "0 (immediate)" },
        "Checks" => lambda {|alert| 
          if alert['allChecks']
            "All"
          else
            checks = alert['checks'] || []
            # if checks.size > 3
            #   checks.first(3).collect {|r| r['name'] }.join(", ") + ", (#{checks.size - 3} more)"
            # else
            #   checks.collect {|r| r['name'] }.join(", ")
            # end
            checks.size.to_s
          end
        },
        "Groups" => lambda {|alert|
          if alert['allGroups']
            "All"
          else
            check_groups = alert['checkGroups'] || []
            # if check_groups.size > 3
            #   check_groups.first(3).collect {|r| r['name'] }.join(", ") + ", (#{check_groups.size - 3} more)"
            # else
            #   check_groups.collect {|r| r['name'] }.join(", ")
            # end
            check_groups.size.to_s
          end
        },
        "Apps" => lambda {|alert| 
          if alert['allApps']
            "All"
          else
            monitor_apps = alert['apps'] || []
            # if monitor_apps.size > 3
            #   monitor_apps.first(3).collect {|r| r['name'] }.join(", ") + ", (#{monitor_apps.size - 3} more)"
            # else
            #   monitor_apps.collect {|r| r['name'] }.join(", ")
            # end
            monitor_apps.size.to_s
          end
        },
        "Recipients" => lambda {|alert| 
          recipients = alert['recipients'] || []
          # if recipients.size > 3
          #   recipients.first(3).collect {|r| r['name'] }.join(", ") + ", (#{recipients.size - 3} more)"
          # else
          #   recipients.collect {|r| r['name'] }.join(", ")
          # end
          recipients.size.to_s
        },
        "Created" => lambda {|alert| format_local_dt(alert['dateCreated']) },
        "Updated" => lambda {|alert| format_local_dt(alert['lastUpdated']) },
      }
      print as_description_list(alert, description_cols)
     


      ## Checks in this Alert
      #checks = alert["checks"]
      checks = json_response["checks"]
      if checks && !checks.empty?
        print_h2 "Checks"
        print_checks_table(checks, options)
      end

      ## Check Groups in this Alert
      # check_groups = alert["checkGroups"]
      check_groups = json_response["checkGroups"]
      if check_groups && !check_groups.empty?
        print_h2 "Check Groups"
        print_check_groups_table(check_groups, options)
      end

      ## Apps in this Alert
      monitor_apps = alert["apps"]
      monitor_apps = json_response["apps"]
      if monitor_apps && !monitor_apps.empty?
        print_h2 "Apps"
        print_monitoring_apps_table(monitor_apps, options)
      end

      ## Recipients in this Alert
      recipients = alert["recipients"]
      if recipients && !recipients.empty?
        print_h2 "Recipients"
        columns = [
          {"CONTACT ID" => lambda {|recipient| recipient['id'] } },
          {"CONTACT NAME" => lambda {|recipient| recipient['name'] } },
          {"METHOD" => lambda {|recipient| format_recipient_method(recipient) } },
          {"NOTIFY ON CHANGE" => lambda {|recipient| format_boolean(recipient['notify']) } },
          {"NOTIFY ON CLOSE" => lambda {|recipient| format_boolean(recipient['close']) } }
        ]
        print as_pretty_table(recipients, columns)
      end

      # show Notify events here...

      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on("--name STRING", String, "Alert name") do |val|
        params['name'] = val
      end
      opts.on('--min-severity VALUE', String, "Min. Severity. Trigger when severity level is reached. Default is critical") do |val|
        params['minSeverity'] = val.to_s.downcase
      end
      opts.on('--min-duration MINUTES', String, "Min. Duration. Trigger after a number of minutes. Default is 0 (immediate)") do |val|
        params['minDuration'] = val.to_i
      end
      opts.on('--all-checks [on|off]', String, "Toggle trigger for all checks.") do |val|
        params['allChecks'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--checks LIST', Array, "Checks, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checks'] = []
        else
          params['checks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--all-groups [on|off]', String, "Toggle trigger for all check groups.") do |val|
        params['allGroups'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--groups LIST', Array, "Check Groups, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checkGroups'] = []
        else
          params['checkGroups'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--all-apps [on|off]', String, "Toggle trigger for all check groups.") do |val|
        params['allApps'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--apps LIST', Array, "Monitor Apps, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['apps'] = []
        else
          params['apps'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--recipients LIST', Array, "Recipients, comma separated list of Contact names or IDs. Additional recipient settings can be passed like Contact ID:method:notifyOnClose:notifyOnChange.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['recipients'] = []
        else
          recipient_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
          params['recipients'] = recipient_list
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a monitoring alert rule." + "\n" +
                    "[name] is required. This is the name of the new alert rule."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
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
        if params['name'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'The name of this alert rule.'}], options[:options])
          params['name'] = v_prompt['name']
        end
        if params['minSeverity'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'minSeverity', 'type' => 'text', 'fieldLabel' => 'Min. Severity', 'required' => false, 'selectOptions' => available_severities, 'defaultValue' => 'critical', 'description' => 'Trigger when severity level is reached.'}], options[:options])
          params['minSeverity'] = v_prompt['minSeverity'].to_s unless v_prompt['minSeverity'].nil?
        end
        if params['minDuration'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'minDuration', 'type' => 'text', 'fieldLabel' => 'Min. Duration', 'required' => false, 'defaultValue' => '0', 'description' => 'Trigger after a number of minutes.'}], options[:options])
          params['minDuration'] = v_prompt['minDuration'].to_i unless v_prompt['minDuration'].nil?
        end
        # All Checks?
        if params['allChecks'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allChecks', 'type' => 'text', 'fieldLabel' => 'All Checks?', 'required' => false, 'defaultValue' => 'off', 'description' => 'Trigger for all checks.'}], options[:options])
          params['allChecks'] = (['on','true'].include?(v_prompt['allChecks'].to_s)) unless v_prompt['allChecks'].nil?
        end
        # Checks
        if params['allChecks'] == true
          params.delete('checks')
        else
          check_list = nil
          check_ids = []
          still_prompting = true
          while still_prompting
            if params['checks'].nil?
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'checks', 'type' => 'text', 'fieldLabel' => 'Checks', 'required' => false, 'description' => 'Checks to include in this alert rule, comma comma separated list of names or IDs.'}], options[:options])
              unless v_prompt['checks'].to_s.empty?
                check_list = v_prompt['checks'].split.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
              end
              bad_ids = []
              if check_list && check_list.size > 0
                check_list.each do |it|
                  found_check = nil
                  begin
                    found_check = find_check_by_name_or_id(it)
                  rescue SystemExit => cmdexit
                  end
                  if found_check
                    check_ids << found_check['id']
                  else
                    bad_ids << it
                  end
                end
              end
              still_prompting = bad_ids.empty? ? false : true
            else
              check_list = params['checks']
              still_prompting = false
              bad_ids = []
              if check_list && check_list.size > 0
                check_list.each do |it|
                  found_check = nil
                  begin
                    found_check = find_check_by_name_or_id(it)
                  rescue SystemExit => cmdexit
                  end
                  if found_check
                    check_ids << found_check['id']
                  else
                    bad_ids << it
                  end
                end
              end
              if !bad_ids.empty?
                return 1
              end
            end
          end
          params['checks'] = check_ids
        end

        # All Check Groups?
        if params['allGroups'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allGroups', 'type' => 'text', 'fieldLabel' => 'All Groups?', 'required' => false, 'defaultValue' => 'off', 'description' => 'Trigger for all check groups.'}], options[:options])
          params['allGroups'] = (['on','true'].include?(v_prompt['allGroups'].to_s)) unless v_prompt['allGroups'].nil?
        end
        # Check Groups
        if params['allGroups'] == true
          params.delete('checkGroups')
        else
          check_group_list = nil
          check_group_ids = []
          still_prompting = true
          while still_prompting
            if params['checkGroups'].nil?
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'checkGroups', 'type' => 'text', 'fieldLabel' => 'Check Groups', 'required' => false, 'description' => 'Check Groups to include in this alert rule, comma separated list of names or IDs.'}], options[:options])
              unless v_prompt['checkGroups'].to_s.empty?
                check_group_list = v_prompt['checkGroups'].split.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
              end
              bad_ids = []
              if check_group_list && check_group_list.size > 0
                check_group_list.each do |it|
                  found_check = nil
                  begin
                    found_check = find_check_group_by_name_or_id(it)
                  rescue SystemExit => cmdexit
                  end
                  if found_check
                    check_group_ids << found_check['id']
                  else
                    bad_ids << it
                  end
                end
              end
              still_prompting = bad_ids.empty? ? false : true
            else
              check_group_list = params['checkGroups']
              still_prompting = false
              bad_ids = []
              if check_group_list && check_group_list.size > 0
                check_group_list.each do |it|
                  found_check = nil
                  begin
                    found_check = find_check_group_by_name_or_id(it)
                  rescue SystemExit => cmdexit
                  end
                  if found_check
                    check_group_ids << found_check['id']
                  else
                    bad_ids << it
                  end
                end
              end
              if !bad_ids.empty?
                return 1
              end
            end
          end
          params['checkGroups'] = check_group_ids
        end

        # All Apps?
        if params['allApps'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allApps', 'type' => 'text', 'fieldLabel' => 'All Apps?', 'required' => false, 'defaultValue' => 'off', 'description' => 'Trigger for all monitoring apps.'}], options[:options])
          params['allApps'] = (['on','true'].include?(v_prompt['allApps'].to_s)) unless v_prompt['allApps'].nil?
        end
        # Apps
        if params['allApps'] == true
          params.delete('apps')
        else
          monitor_app_list = nil
          monitor_app_ids = []
          still_prompting = true
          while still_prompting
            if params['apps'].nil?
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'apps', 'type' => 'text', 'fieldLabel' => 'Apps', 'required' => false, 'description' => 'Monitor Apps to include in this alert rule, comma separated list of names or IDs.'}], options[:options])
              unless v_prompt['apps'].to_s.empty?
                monitor_app_list = v_prompt['apps'].split.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
              end
              bad_ids = []
              if monitor_app_list && monitor_app_list.size > 0
                monitor_app_list.each do |it|
                  found_monitor_app = nil
                  begin
                    found_monitor_app = find_monitoring_app_by_name_or_id(it)
                  rescue SystemExit => cmdexit
                  end
                  if found_monitor_app
                    monitor_app_ids << found_monitor_app['id']
                  else
                    bad_ids << it
                  end
                end
              end
              still_prompting = bad_ids.empty? ? false : true
            else
              monitor_app_list = params['apps']
              still_prompting = false
              bad_ids = []
              if monitor_app_list && monitor_app_list.size > 0
                monitor_app_list.each do |it|
                  found_monitor_app = nil
                  begin
                    found_monitor_app = find_monitoring_app_by_name_or_id(it)
                  rescue SystemExit => cmdexit
                  end
                  if found_monitor_app
                    monitor_app_ids << found_monitor_app['id']
                  else
                    bad_ids << it
                  end
                end
              end
              if !bad_ids.empty?
                return 1
              end
            end
          end
          params['apps'] = monitor_app_ids
        end

        # Recipients (Contacts)
        recipient_list = []
        contact_ids = []
          
        if params['recipients'].nil?
          still_prompting = true
          while still_prompting
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'recipients', 'type' => 'text', 'fieldLabel' => 'Recipients', 'required' => false, 'description' => "Recipients, comma separated list of contact names or IDs. Additional recipient settings can be passed like Contact ID:method:notifyOnClose:notifyOnChange"}], options[:options])
            unless v_prompt['recipients'].to_s.empty?
              recipient_list = v_prompt['recipients'].split.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
            end
            bad_ids = []
            if recipient_list && recipient_list.size > 0
              recipient_list.each do |it|
                found_contact = nil
                begin
                  parts = it.split(":").collect { |part| part.strip }
                  found_contact = find_contact_by_name_or_id(parts[0])
                rescue SystemExit => cmdexit
                end
                if found_contact
                  contact_ids << found_contact['id']
                else
                  bad_ids << it
                end
              end
            end
            still_prompting = bad_ids.empty? ? false : true
          end
        else
          recipient_list = params['recipients']
          bad_ids = []
          if recipient_list && recipient_list.size > 0
            recipient_list.each do |it|
              found_contact = nil
              begin
                parts = it.split(":").collect { |part| part.strip }
                found_contact = find_contact_by_name_or_id(parts[0])
              rescue SystemExit => cmdexit
              end
              if found_contact
                contact_ids << found_contact['id']
              else
                bad_ids << it
              end
            end
          end
          if !bad_ids.empty?
            return 1
          end
        end
        recipient_records = []
        # parse recipient string as Contact ID:method:notifyOnClose:notifyOnChange
        recipient_list.each_with_index do |it, index|
          parts = it.split(":").collect { |part| part.strip }
          #recipient_id = parts[0]
          recipient_id = contact_ids[index]
          recipient_method = parts[1] ? parts[1].to_s : "emailAddress"
          recipient_notify = parts[2] ? ['on','true'].include?(parts[2].to_s.downcase) : true
          recipient_close = parts[3] ? ['on','true'].include?(parts[3].to_s.downcase) : true
          recipient_record = {
            "id" => recipient_id, 
            "method" => parse_recipient_method(recipient_method), 
            "notify" => recipient_notify,
            "close" => recipient_close
          }
          recipient_records << recipient_record
        end
        params['recipients'] = recipient_records
        
        payload = {'alert' => params}
      end

      @monitoring_alerts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_alerts_interface.dry.create(payload)
        return
      end

      json_response = @monitoring_alerts_interface.create(payload)
      alert = json_response['alert']
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Created alert (#{alert['id']}) #{alert['name']}"
        #_get(alert['id'], options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[alert]")
      opts.on("--name STRING", String, "Alert name") do |val|
        params['name'] = val
      end
      opts.on("--name STRING", String, "Alert name") do |val|
        params['name'] = val
      end
      opts.on('--min-severity VALUE', String, "Min. Severity. Trigger when severity level is reached. Default is critical") do |val|
        params['minSeverity'] = val.to_s.downcase
      end
      opts.on('--min-duration MINUTES', String, "Min. Duration. Trigger after a number of minutes. Default is 0 (immediate)") do |val|
        params['minDuration'] = val.to_i
      end
      opts.on('--all-checks [on|off]', String, "Toggle trigger for all checks.") do |val|
        params['allChecks'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--checks LIST', Array, "Checks, comma separated list of names or IDs.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checks'] = []
        else
          params['checks'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--all-groups [on|off]', String, "Toggle trigger for all check groups.") do |val|
        params['allGroups'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--groups LIST', Array, "Check Groups, comma separated list of check group ID or names.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['checkGroups'] = []
        else
          params['checkGroups'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--all-apps [on|off]', String, "Toggle trigger for all check groups.") do |val|
        params['allApps'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--apps LIST', Array, "Monitor Apps, comma separated list of monitor app ID or names.") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['apps'] = []
        else
          params['apps'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--recipients LIST', Array, "Recipients, comma separated list of contact ID or names. Additional recipient settings can be passed like Contact ID:method:notifyOnClose:notifyOnChange") do |list|
        if list.size == 1 && ('[]' == list[0]) # clear array
          params['recipients'] = []
        else
          recipient_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
          params['recipients'] = recipient_list
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update a monitoring alert rule." + "\n" +
                    "[alert] is required. This is the name or ID of the alert rule."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)

    begin
      alert = find_alert_by_name_or_id(args[0])

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # if params['name'].nil?
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'The name of this alert rule.'}], options[:options])
        #   params['name'] = v_prompt['name']
        # end
        # if params['minSeverity'].nil?
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'minSeverity', 'type' => 'text', 'fieldLabel' => 'Min. Severity', 'required' => false, 'selectOptions' => available_severities, 'defaultValue' => 'critical', 'description' => 'Trigger when severity level is reached.'}], options[:options])
        #   params['minSeverity'] = v_prompt['minSeverity'].to_s unless v_prompt['minSeverity'].nil?
        # end
        # if params['minDuration'].nil?
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'minDuration', 'type' => 'text', 'fieldLabel' => 'Min. Duration', 'required' => false, 'defaultValue' => '0', 'description' => 'Trigger after a number of minutes.'}], options[:options])
        #   params['minDuration'] = v_prompt['minDuration'].to_i unless v_prompt['minDuration'].nil?
        # end
        # All Checks?
        # if params['allChecks'].nil?
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allChecks', 'type' => 'text', 'fieldLabel' => 'All Checks?', 'required' => false, 'defaultValue' => 'off', 'description' => 'Trigger for all checks.'}], options[:options])
        #   params['allChecks'] = (['on','true'].include?(v_prompt['allChecks'].to_s)) unless v_prompt['allChecks'].nil?
        # end
        # Checks
        if params['checks']
          check_list = params['checks']
          check_ids = []

          bad_ids = []
          if check_list && check_list.size > 0
            check_list.each do |it|
              found_check = nil
              begin
                found_check = find_check_by_name_or_id(it)
              rescue SystemExit => cmdexit
              end
              if found_check
                check_ids << found_check['id']
              else
                bad_ids << it
              end
            end
          end
          if !bad_ids.empty?
            return 1
          end
          
          params['checks'] = check_ids
        end

        # All Check Groups?
        # if params['allGroups'].nil?
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allGroups', 'type' => 'text', 'fieldLabel' => 'All Groups?', 'required' => false, 'defaultValue' => 'off', 'description' => 'Trigger for all check groups.'}], options[:options])
        #   params['allGroups'] = (['on','true'].include?(v_prompt['allGroups'].to_s)) unless v_prompt['allGroups'].nil?
        # end
        # Check Groups
        if params['checkGroups']
          check_group_list = params['checkGroups']
          check_group_ids = []
          bad_ids = []
          if check_group_list && check_group_list.size > 0
            check_group_list.each do |it|
              found_check = nil
              begin
                found_check = find_check_group_by_name_or_id(it)
              rescue SystemExit => cmdexit
              end
              if found_check
                check_group_ids << found_check['id']
              else
                bad_ids << it
              end
            end
          end
          if !bad_ids.empty?
            return 1
          end
          params['checkGroups'] = check_group_ids
        end
        
        # All Apps?
        # if params['allApps'].nil?
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allApps', 'type' => 'text', 'fieldLabel' => 'All Apps?', 'required' => false, 'defaultValue' => 'off', 'description' => 'Trigger for all monitoring apps.'}], options[:options])
        #   params['allApps'] = (['on','true'].include?(v_prompt['allApps'].to_s)) unless v_prompt['allApps'].nil?
        # end
        # Apps
        if params['checkGroups']
          monitor_app_list = params['apps']
          monitor_app_ids = []
          bad_ids = []
          if monitor_app_list && monitor_app_list.size > 0
            monitor_app_list.each do |it|
              found_monitor_app = nil
              begin
                found_monitor_app = find_monitoring_app_by_name_or_id(it)
              rescue SystemExit => cmdexit
              end
              if found_monitor_app
                monitor_app_ids << found_monitor_app['id']
              else
                bad_ids << it
              end
            end
          end
          if !bad_ids.empty?
            return 1
          end
          params['apps'] = monitor_app_ids
        end

        # Recipients (Contacts)
        if params['recipients']
          
          recipient_list = params['recipients']
          contact_ids = []
          bad_ids = []
          if recipient_list && recipient_list.size > 0
            recipient_list.each do |it|
              found_contact = nil
              begin
                parts = it.split(":").collect { |part| part.strip }
                found_contact = find_contact_by_name_or_id(parts[0])
              rescue SystemExit => cmdexit
              end
              if found_contact
                contact_ids << found_contact['id']
              else
                bad_ids << it
              end
            end
          end
          if !bad_ids.empty?
            return 1
          end
          recipient_records = []
          # parse recipient string as Contact ID:method:notifyOnClose:notifyOnChange
          # todo: should be smarter and try to merge changes with existing recipient record
          recipient_list.each_with_index do |it, index|
            parts = it.split(":").collect { |part| part.strip }
            #recipient_id = parts[0]
            recipient_id = contact_ids[index]
            recipient_method = parts[1] ? parts[1].to_s : "emailAddress"
            recipient_notify = parts[2] ? ['on','true'].include?(parts[2].to_s.downcase) : true
            recipient_close = parts[3] ? ['on','true'].include?(parts[3].to_s.downcase) : true
            recipient_record = {
              "id" => recipient_id, 
              "method" => parse_recipient_method(recipient_method), 
              "notify" => recipient_notify,
              "close" => recipient_close
            }
            recipient_records << recipient_record
          end
          params['recipients'] = recipient_records
        end
        
        payload = {'alert' => params}
      end

      if params.empty?
        print_red_alert "Specify at least one option to update"
        puts optparse
        exit 1
      end

      @monitoring_alerts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_alerts_interface.dry.update(alert["id"], payload)
        return
      end

      json_response = @monitoring_alerts_interface.update(alert["id"], payload)
      alert = json_response['alert']
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated alert (#{alert['id']}) #{alert['name']}"
        _get(alert['id'], options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[alert]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Delete a monitoring alert rule." + "\n" +
                    "[alert] is required. This is the name or ID of the alert rule. Supports 1-N [alert] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete alert #{id_list.size == 1 ? 'alert' : 'alerts'} #{anded_list(id_list)}?", options)
      exit 1
    end
    return run_command_for_each_arg(id_list) do |arg|
      _remove(arg, options)
    end
  end

  def _remove(id, options)

    begin
      alert = find_alert_by_name_or_id(id)
      @monitoring_alerts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_alerts_interface.dry.destroy(alert['id'])
        return
      end
      json_response = @monitoring_alerts_interface.destroy(alert['id'])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success json_response["msg"] || "Alert (#{alert['id']}) #{alert['name']} deleted"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def print_alerts_table(alerts, options={})
    columns = [
      {"ID" => "id" },
      {"NAME" => "name" },
      {"MIN. SEVERITY" => "minSeverity" },
      {"CHECKS" => lambda {|alert| 
        if alert['allChecks']
          "All"
        else
          checks = alert['checks'] || []
          # if checks.size > 3
          #   checks.first(3).collect {|r| r['name'] }.join(", ") + ", (#{checks.size - 3} more)"
          #   # checks.size.to_s
          # else
          #   checks.collect {|r| r['name'] }.join(", ")
          # end
          checks.size.to_s
        end
      } },
      {"GROUPS" => lambda {|alert| 
        if alert['allGroups']
          "All"
        else
          check_groups = alert['checkGroups'] || []
          # if check_groups.size > 3
          #   check_groups.first(3).collect {|r| r['name'] }.join(", ") + ", (#{check_groups.size - 3} more)"
          # else
          #   check_groups.collect {|r| r['name'] }.join(", ")
          # end
          check_groups.size.to_s
        end
      } },
      {"APPS" => lambda {|alert| 
        if alert['allApps']
          "All"
        else
          monitor_apps = alert['apps'] || []
          # if monitor_apps.size > 3
          #   monitor_apps.first(3).collect {|r| r['name'] }.join(", ") + ", (#{monitor_apps.size - 3} more)"
          # else
          #   monitor_apps.collect {|r| r['name'] }.join(", ")
          # end
          monitor_apps.size.to_s
        end
      } },
      {"RECIPIENTS" => lambda {|alert| 
        recipients = alert['recipients'] || []
        # if recipients.size > 3
        #   recipients.first(3).collect {|r| r['name'] }.join(", ") + ", (#{recipients.size - 3} more)"
        # else
        #   recipients.collect {|r| r['name'] }.join(", ")
        # end
        recipients.size.to_s
      } },
    ]
    if options[:include_fields]
      columns = options[:include_fields]
    end
    print as_pretty_table(alerts, columns, options)
  end

  
end
