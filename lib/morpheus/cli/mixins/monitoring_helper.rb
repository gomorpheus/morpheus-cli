require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for the monitoring domain, incidents, checks, 'n such
module Morpheus::Cli::MonitoringHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def monitoring_interface
    # @api_client.monitoring
    raise "#{self.class} has not defined @monitoring_interface" if @monitoring_interface.nil?
    @monitoring_interface
  end

  def find_check_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_check_by_id(val)
    else
      return find_check_by_name(val)
    end
  end

  def find_check_by_id(id)
    begin
      json_response = monitoring_interface.checks.get(id.to_i)
      return json_response['check']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Check not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_check_by_name(name)
    json_results = monitoring_interface.checks.list({name: name})
    if json_results['checks'].empty?
      print_red_alert "Check not found by name #{name}"
      exit 1
    end
    check = json_results['checks'][0]
    return check
  end

  # def find_incident_by_name_or_id(val)
  #   if val.to_s =~ /\A\d{1,}\Z/
  #     return find_incident_by_id(val)
  #   else
  #     return find_incident_by_name(val)
  #   end
  # end

  def find_incident_by_id(id)
    begin
      json_response = monitoring_interface.incidents.get(id.to_i)
      return json_response['incident']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Incident not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  # def find_incident_by_name(name)
  #   json_results = monitoring_interface.incidents.get({name: name})
  #   if json_results['incidents'].empty?
  #     print_red_alert "Incident not found by name #{name}"
  #     exit 1
  #     end
  #   incident = json_results['incidents'][0]
  #   return incident
  # end


  def get_available_check_types(refresh=false)
    if !@available_check_types || refresh
      # @available_check_types = [{name: 'A Fake Check Type', code: 'achecktype'}]
      # todo: use options api instead probably...
      @available_check_types = check_types_interface.list_check_types['checkTypes']
    end
    return @available_check_types
  end

  def check_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return check_type_for_id(val)
    else
      return check_type_for_name(val)
    end
  end
  
  def check_type_for_id(id)
    return get_available_check_types().find { |z| z['id'].to_i == id.to_i}
  end

  def check_type_for_name(name)
    return get_available_check_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

  def format_severity(severity, return_color=cyan)
    out = ""
    status_string = severity
    if status_string == 'critical'
      out << "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'warning'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    elsif status_string == 'info'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    else
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    end
    out
  end


  def format_health_status(item, return_color=cyan)
    out = ""
    if item
      attrs = {}
      attrs[:unknown] = item['lastRunDate'] ? false : true
      attrs[:muted] = item['createIncident'] == false
      attrs[:failure] = item['lastCheckStatus'] == 'error'
      attrs[:health] = item['health'] ? item['health'].to_i : 0
      
      if attrs[:unknown]
        out << "#{cyan}UNKNOWN#{return_color}"
      elsif attrs[:health] >= 10
        out << "#{green}HEALTHY#{return_color}"
      elsif attrs[:failure]
        out << "#{red}ERROR#{return_color}"
      else
        out << "#{yellow}CAUTION#{return_color}"
      end
      if attrs[:muted]
        out << "#{cyan} (Muted)#{return_color}"
      end
    end
    out
  end

  def format_monitoring_issue_attachment_type(issue)
    if issue["app"]
      "App"
    elsif issue["check"]
      "Check"
    elsif issue["checkGroup"]
      "Group"
    else
      "Severity Change"
    end
  end

  def format_monitoring_incident_status(incident)
    out = ""
    muted = incident['inUptime'] == false
    status_string = incident['status']
    if status_string == 'closed'
      out << "CLOSED ✓"
    else
      out << status_string.to_s.upcase
      if muted
        out << " (MUTED)"
      end
    end
    out
  end

  def format_monitoring_issue_status(issue)
    format_monitoring_incident_status(issue)
  end

  

  # Incidents

  def print_incidents_table(incidents, opts={})
    columns = [
      {"ID" => lambda {|incident| incident['id'] } },
      {"SEVERITY" => lambda {|incident| format_severity(incident['severity']) } },
      {"NAME" => lambda {|incident| incident['name'] || 'No Subject' } },
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


  # Checks

  def format_monitoring_check_status(check, include_msg=false, return_color=cyan)
    out = ""
    unknown = check['lastRunDate'].nil?
    failure = check['lastCheckStatus'] == 'error'
    health = check['health']
    muted = check['createIncident'] == false
    status_string = check['lastCheckStatus'].to_s # null for groups, ignore?

    if unknown
      out << "#{white}UNKNOWN#{return_color}"
    elsif failure || health == 0
      if include_msg && check['lastError']
        out << "#{red}ERROR - #{check['lastError']}#{return_color}"
      else
        out << "#{red}ERROR#{return_color}"
      end
    elsif health.to_i >= 10
      out << "#{green}HEALTHY#{return_color}"
    else
      out << "#{yellow}WARNING#{return_color}"
    end
    if muted
      out << " (MUTED)"
    end
    out
  end

  def format_monitoring_check_last_metric(check)
    if check['lastMetric']
      metric_name = check['checkType'] ? check['checkType']['metricName'] : nil
      if metric_name
        "#{check['lastMetric']} #{metric_name}"
      else
        "#{check['lastMetric']}"
      end
    else
      "N/A" 
    end
  end

  def format_monitoring_check_type(check)
    out = ""
    if check['checkType']
      if check['checkType']['code'] == 'mixedCheck' || check['checkType']['code'] == 'mixed'
        out = check['checkType']["name"] || "Mixed"
      else
        out = check['checkType']["name"] || ""
      end
    end
    out
  end

  def print_checks_table(checks, opts={})
    columns = [
      {"ID" => lambda {|check| check['id'] } },
      {"STATUS" => lambda {|check| format_monitoring_check_status(check) } },
      {"NAME" => lambda {|check| check['name'] } },
      {"TIME" => lambda {|check| check['lastRunDate'] ? format_local_dt(check['lastRunDate']) : "N/A" } },
      {"AVAILABILITY" => {display_method: lambda {|check| check['availability'] ? "#{check['availability'].to_f.round(3).to_s}%" : "N/A"} }, justify: "center" },
      {"RESPONSE TIME" => {display_method: lambda {|check| check['lastTimer'] ? "#{check['lastTimer']}ms" : "N/A" } }, justify: "center" },
      {"LAST METRIC" => {display_method: lambda {|check| format_monitoring_check_last_metric(check) } }, justify: "center" },
      {"TYPE" => lambda {|check| format_monitoring_check_type(check) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(checks, columns, opts)
  end

  def print_check_history_table(history_items, opts={})
    columns = [
      {"STATUS" => lambda {|issue| format_health_status(issue) } },
      {"DATE CHECKED" => lambda {|issue| format_local_dt(issue['lastRunDate']) } },
      # {"NAME" => lambda {|issue| issue['name'] } },
      # {"AVAILABLE" => lambda {|issue| format_boolean issue['createIncident'] } },
      {"RESPONSE TIME" => lambda {|issue| issue["lastTimer"] ? "#{issue['lastTimer']}ms" : "" } }, 
      {"LAST METRIC" => lambda {|issue| issue["lastMetric"] } }, 
      {"MESSAGE" => lambda {|issue| 
        # issue["lastError"].to_s.empty? ? issue["lastMessage"] : issue["lastError"]
        if issue['lastCheckStatus'] == 'error'
          issue["lastError"].to_s
        else
          issue["lastMessage"]
        end
      } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(history_items, columns, opts)
  end

  def print_check_group_history_table(history_items, opts={})
    columns = [
      {"STATUS" => lambda {|issue| format_health_status(issue) } },
      {"DATE CHECKED" => lambda {|issue| format_local_dt(issue['lastRunDate']) } },
      {"CHECK" => lambda {|issue| issue['name'] } },
      # {"AVAILABLE" => lambda {|issue| format_boolean issue['createIncident'] } },
      {"RESPONSE TIME" => lambda {|issue| issue["lastTimer"] ? "#{issue['lastTimer']}ms" : "" } }, 
      {"LAST METRIC" => lambda {|issue| issue["lastMetric"] } }, 
      {"MESSAGE" => lambda {|issue| 
        # issue["lastError"].to_s.empty? ? issue["lastMessage"] : issue["lastError"]
        if issue['lastCheckStatus'] == 'error'
          issue["lastError"].to_s
        else
          issue["lastMessage"]
        end
      } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(history_items, columns, opts)
  end

  def print_monitor_app_history_table(history_items, opts={})
    print_check_group_history_table(history_items, opts)
  end

  def print_check_notifications_table(notifications, opts={})
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

  # Monitoring Contacts

  def find_contact_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_contact_by_id(val)
    else
      return find_contact_by_name(val)
    end
  end

  def find_contact_by_id(id)
    begin
      json_response = monitoring_interface.contacts.get(id.to_i)
      return json_response['contact']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Contact not found by id #{id}"
        exit 1 # return nil
      else
        raise e
      end
    end
  end

  def find_contact_by_name(name)
    json_results = monitoring_interface.contacts.list({name: name})
    contacts = json_results["contacts"]
    if contacts.empty?
      print_red_alert "Contact not found by name #{name}"
      exit 1 # return nil
    elsif contacts.size > 1
      print_red_alert "#{contacts.size} Contacts found by name #{name}"
      print "\n"
      puts as_pretty_table(contacts, [{"ID" => "id" }, {"NAME" => "name"}, {"EMAIL" => "emailAddress"}], {color: red})
      print_red_alert "Try passing ID instead"
      print reset,"\n"
      exit 1 # return nil
    else
      return contacts[0]
    end
  end

  # Monitoring Alerts

  def find_alert_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_alert_by_id(val)
    else
      return find_alert_by_name(val)
    end
  end

  def find_alert_by_id(id)
    begin
      json_response = monitoring_interface.alerts.get(id.to_i)
      return json_response['alert']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Alert not found by id #{id}"
        exit 1 # return nil
      else
        raise e
      end
    end
  end

  def find_alert_by_name(name)
    json_results = monitoring_interface.alerts.list({name: name})
    alerts = json_results["alerts"]
    if alerts.empty?
      print_red_alert "Alert not found by name #{name}"
      exit 1 # return nil
    elsif alerts.size > 1
      print_red_alert "#{alerts.size} Alerts found by name #{name}"
      print "\n"
      puts as_pretty_table(alerts, [{"ID" => "id" }, {"NAME" => "name"}], {color: red})
      print_red_alert "Try passing ID instead"
      print reset,"\n"
      exit 1 # return nil
    else
      return alerts[0]
    end
  end

  # Monitoring Check Groups

  def find_check_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_check_group_by_id(val)
    else
      return find_check_group_by_name(val)
    end
  end

  def find_check_group_by_id(id)
    begin
      json_response = monitoring_interface.groups.get(id.to_i)
      return json_response['checkGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Check Group not found by id #{id}"
        exit 1 # return nil
      else
        raise e
      end
    end
  end

  def find_check_group_by_name(name)
    json_results = monitoring_interface.groups.list({name: name})
    groups = json_results["checkGroups"]
    if groups.empty?
      print_red_alert "Check Group not found by name #{name}"
      exit 1 # return nil
    elsif groups.size > 1
      print_red_alert "#{groups.size} Check Groups found by name #{name}"
      print "\n"
      puts as_pretty_table(groups, [{"ID" => "id" }, {"NAME" => "name"}], {color: red})
      print_red_alert "Try passing ID instead"
      print reset,"\n"
      exit 1 # return nil
    else
      return groups[0]
    end
  end

  def print_check_groups_table(check_groups, opts={})
    columns = [
      {"ID" => lambda {|check| check['id'] } },
      {"STATUS" => lambda {|check| format_monitoring_check_status(check) } },
      {"NAME" => lambda {|check| check['name'] } },
      {"TIME" => lambda {|check| check['lastRunDate'] ? format_local_dt(check['lastRunDate']) : "N/A" } },
      {"AVAILABILITY" => {display_method: lambda {|check| check['availability'] ? "#{check['availability'].to_f.round(3).to_s}%" : "N/A"} }, justify: "center" },
      {"RESPONSE TIME" => {display_method: lambda {|check| check['lastTimer'] ? "#{check['lastTimer']}ms" : "N/A" } }, justify: "center" },
      # {"LAST METRIC" => {display_method: lambda {|check| format_monitoring_check_last_metric(check) } }, justify: "center" },
      {"TYPE" => lambda {|check| format_monitoring_check_type(check) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(check_groups, columns, opts)
  end

  # Monitoring apps

  def find_monitoring_app_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_monitoring_app_by_id(val)
    else
      return find_monitoring_app_by_name(val)
    end
  end

  def find_monitoring_app_by_id(id)
    begin
      json_response = monitoring_interface.apps.get(id.to_i)
      return json_response['monitorApp'] || json_response['app']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Monitor App not found by id #{id}"
        exit 1 # return nil
      else
        raise e
      end
    end
  end

  def find_monitoring_app_by_name(name)
    json_results = monitoring_interface.apps.list({name: name})
    apps = json_results["monitorApps"] || json_results["apps"]
    if apps.empty?
      print_red_alert "Monitor App not found by name #{name}"
      exit 1 # return nil
    elsif apps.size > 1
      print_red_alert "#{apps.size} apps found by name #{name}"
      print "\n"
      puts as_pretty_table(apps, [{"ID" => "id" }, {"NAME" => "name"}], {color: red})
      print_red_alert "Try passing ID instead"
      print reset,"\n"
      exit 1 # return nil
    else
      return apps[0]
    end
  end

  def print_monitoring_apps_table(apps, opts={})
    columns = [
      {"ID" => lambda {|app| app['id'] } },
      {"STATUS" => lambda {|app| format_monitoring_check_status(app) } },
      {"NAME" => lambda {|app| app['name'] } },
      # {"DESCRIPTION" => lambda {|app| app['description'] } },
      {"TIME" => lambda {|app| app['lastRunDate'] ? format_local_dt(app['lastRunDate']) : "N/A" } },
      {"AVAILABILITY" => {display_method: lambda {|app| app['availability'] ? "#{app['availability'].to_f.round(3).to_s}%" : "N/A"} }, justify: "center" },
      {"RESPONSE TIME" => {display_method: lambda {|app| app['lastTimer'] ? "#{app['lastTimer']}ms" : "N/A" } }, justify: "center" },
      #{"LAST METRIC" => {display_method: lambda {|app| app['lastMetric'] ? "#{app['lastMetric']}" : "N/A" } }, justify: "center" },
      {"CHECKS" => lambda {|app| 
        checks = app['checks']
        checks_str = ""
        if checks && checks.size > 0
          checks_str = "#{checks.size} #{checks.size == 1 ? 'check' : 'checks'}"
          # checks_str << " [#{checks.join(', ')}]"
        end
        check_groups = app['checkGroups']
        check_groups_str = ""
        if check_groups && check_groups.size > 0
          check_groups_str = "#{check_groups.size} #{check_groups.size == 1 ? 'group' : 'groups'}"
          # check_groups_str << " [#{check_groups.join(', ')}]"
        end
        [checks_str, check_groups_str].reject {|s| s.empty? }.join(", ")
      } },
      
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(apps, columns, opts)
  end

  def available_severities
    [
      [name:'Critical', code:'critical', value:'critical'],
      [name:'Warning', code:'warning', value:'warning'],
      [name:'Info', code:'info', value:'info']
    ]
  end

  def format_recipient_method(recipient)
    meth = recipient['method'].to_s
    alert_method_names = []
    if meth =~ /email/i
      alert_method_names << "Email"
    end
    if meth =~ /sms/i
      alert_method_names << "SMS"
    end
    if meth =~ /apn/i
      alert_method_names << "APN"
    end
    # if alert_method_names.empty?
    #   alert_method_names << "None"
    # end
    anded_list(alert_method_names)
  end

  # server expects "emailAddress" or "smsAddress" or "emailAddress,smsAddress"
  def parse_recipient_method(meth)
    requested_methods = meth.to_s
    alert_methods = []
    if meth =~ /email/i
      alert_methods << "emailAddress"
    end
    if meth =~ /sms/i || meth =~ /phone/i || meth =~ /mobile/i
      alert_methods << "smsAddress"
    end
    if meth =~ /apn/i
      alert_methods << "apns"
    end
    alert_methods.join(',')
  end

  def prompt_for_recipients(params, options={})
    #todo
  end

  def prompt_for_check_groups(params, options={}, api_client=nil, api_params={})
  # def prompt_for_check_groups(params, options={})
    # Check Groups
    check_group_list = nil
    check_group_ids = []
    still_prompting = true
    
    if params['checkGroups'].nil?
      while still_prompting
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'checkGroups', 'type' => 'text', 'fieldLabel' => 'Check Groups', 'required' => false, 'description' => 'Check Groups to include in this alert rule, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['checkGroups'].to_s.empty?
          check_group_list = v_prompt['checkGroups'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
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
      end
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
        return {success:false, msg:"Check Groups not found: #{bad_ids}"}
      end
      # return check_group_ids
      # payload = {'checkGroups':check_group_ids}
      # return payload
      return {success:true, data: check_group_ids}
    end
  end

  def prompt_for_checks(params, options={}, api_client=nil, api_params={})
    # Checks
    check_list = nil
    check_ids = nil
    still_prompting = true
    if params['checks'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'checks', 'type' => 'text', 'fieldLabel' => 'Checks', 'required' => false, 'description' => 'Checks to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['checks'].to_s.empty?
          check_list = v_prompt['checks'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
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
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      check_list = params['checks']
      still_prompting = false
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
        return {success:false, msg:"Checks not found: #{bad_ids}"}
      end
    end
    return {success:true, data: check_ids}
  end

  def prompt_for_check_groups(params, options={}, api_client=nil, api_params={})
  # def prompt_for_check_groups(params, options={})
    # Check Groups
    check_group_list = nil
    check_group_ids = nil
    bad_ids = []
    if params['checkGroups'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'checkGroups', 'type' => 'text', 'fieldLabel' => 'Check Groups', 'required' => false, 'description' => 'Check Groups to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['checkGroups'].to_s.empty?
          check_group_list = v_prompt['checkGroups'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
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
        still_prompting = bad_ids.empty? ? false : true
      end
    else
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
        return {success:false, msg:"Check Groups not found: #{bad_ids}"}
      end
    end
    return {success:true, data: check_group_ids}
  end

  def prompt_for_monitor_apps(params, options={}, api_client=nil, api_params={})
    # Apps
      
    monitor_app_list = nil
    monitor_app_ids = nil
    if params['apps'].nil?
      still_prompting = true
      while still_prompting
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'apps', 'type' => 'text', 'fieldLabel' => 'Apps', 'required' => false, 'description' => 'Monitor Apps to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['apps'].to_s.empty?
          monitor_app_list = v_prompt['apps'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        check_group_ids = []
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
      end
    else
      monitor_app_list = params['apps']
      check_group_ids = []
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
        return {success:false, msg:"Monitor Apps not found: #{bad_ids}"}
      end
    end
    return {success:true, data: monitor_app_ids}
  end
end
