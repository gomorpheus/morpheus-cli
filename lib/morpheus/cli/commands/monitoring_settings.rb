require 'morpheus/cli/cli_command'

class Morpheus::Cli::MonitoringSettings
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'monitoring-settings'
  set_command_description "View and manage monitoring settings"
  register_subcommands :get, :update

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_settings_interface = @api_client.monitoring_settings
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = "Get monitoring settings."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    params.merge!(parse_query_options(options))
    @monitoring_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @monitoring_settings_interface.dry.get(options)
      return
    end
    json_response = @monitoring_settings_interface.get(options)
    render_response(json_response, options, 'monitoringSettings') do
      monitoring_settings = json_response['monitoringSettings']
      service_now_settings = monitoring_settings['serviceNow']
      new_relic_settings = monitoring_settings['newRelic']
      print_h1 "Monitoring Settings"
      print cyan
      description_cols = {
        "Auto Create Checks" => lambda {|it| format_boolean(it['autoManageChecks']) },
        "Availability Time Frame" => lambda {|it| it['availabilityTimeFrame'] ? it['availabilityTimeFrame'].to_s + ' days' : '' },
        "Availability Precision" => lambda {|it| it['availabilityPrecision'] ? it['availabilityPrecision'].to_s : '' },
        "Default Check Interval" => lambda {|it| it['defaultCheckInterval'] ? it['defaultCheckInterval'].to_s + ' minutes' : '' },
      }
      print_description_list(description_cols, monitoring_settings, options)
      if service_now_settings['enabled']
        print_h2 "Service Now Settings", options.merge(:border_style => :thin)
        description_cols = service_now_settings['enabled'] ? {
          "Enabled" => lambda {|it| format_boolean(it['enabled']) },
          "Integration" => lambda {|it| it['integration'] ? it['integration']['name'] : '' },
          "New Incident Action" => lambda {|it| it['newIncidentAction'] },
          "Close Incident Action" => lambda {|it| it['closeIncidentAction'] },
          "Info Mapping" => lambda {|it| it['infoMapping'] },
          "Warning Mapping" => lambda {|it| it['warningMapping'] },
          "Critical Mapping" => lambda {|it| it['criticalMapping'] },
        } : {
          "Enabled" => lambda {|it| format_boolean(it['enabled']) },
        }
        print_description_list(description_cols, service_now_settings)
      end
      if new_relic_settings['enabled']
        print_h2 "New Relic Settings", options.merge(:border_style => :thin)
        description_cols = new_relic_settings['enabled'] ? {
          "Enabled" => lambda {|it| format_boolean(it['enabled']) },
          "License Key" => lambda {|it| it['licenseKey'] },
        } : {
          "Enabled" => lambda {|it| format_boolean(it['enabled']) },
        }
        print_description_list(description_cols, new_relic_settings, options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def update(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      opts.on('--auto-create-checks [on|off]', String, "Auto Create Checks") do |val|
        params['autoManageChecks'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--availability-time-frame DAYS", Integer, "Availability Time Frame. The number of days availability should be calculated for. Changes will not take effect until your checks have passed their check interval.") do |val|
        params['availabilityTimeFrame'] = val.to_i
      end
      opts.on("--availability-precision DIGITS", Integer, "Availability Precision. The number of decimal places availability should be displayed in. Can be anywhere between 0 and 5.") do |val|
        params['availabilityPrecision'] = val.to_i
      end
      opts.on("--default-check-interval MINUTES", Integer, "Default Check Interval. The default interval to use when creating new checks. Value is in minutes.") do |val|
        params['defaultCheckInterval'] = val.to_i
      end
      opts.on('--service-now-enabled [on|off]', String, "Service Now: Enabled (on) or disabled (off)") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--service-now-integration ID', String, "Service Now: Integration ID or Name") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['integration'] = val # {'id' => val.to_i}
      end
      opts.on("--service-now-new-incident-action create|none", String, "Service Now: New Incident Action") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['newIncidentAction'] = val
      end
      opts.on("--service-now-close-incident-action close|activity|none", String, "Service Now: Close Incident Action") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['closeIncidentAction'] = val
      end
      opts.on("--service-now-info-mapping low|medium|high", String, "Service Now: Info Mapping") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['infoMapping'] = val
      end
      opts.on("--service-now-warning-mapping low|medium|high", String, "Service Now: Warning Mapping") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['warningMapping'] = val
      end
      opts.on("--service-now-critical-mapping low|medium|high", String, "Service Now: Critical Mapping") do |val|
        params['serviceNow'] ||= {}
        params['serviceNow']['criticalMapping'] = val
      end
      opts.on('--new-relic-enabled [on|off]', String, "New Relic: Enabled (on) or disabled (off)") do |val|
        params['newRelic'] ||= {}
        params['newRelic']['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--new-relic-license-key VALUE", String, "New Relic: License Key") do |val|
        params['newRelic'] ||= {}
        params['newRelic']['licenseKey'] = val
      end
      build_standard_update_options(opts, options)
      opts.footer = "Update monitoring settings."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    payload = parse_payload(options)
    if !payload
      payload = {}
      payload.deep_merge!({object_key => parse_passed_options(options)}) # inject options passed with -O foo=bar
      if params['serviceNow'] && params['serviceNow']['integration']
        integration = find_by_name_or_id(:integration, params['serviceNow']['integration'])
        if integration.nil?
          exit 1 #return 1, "Integration not found by '#{options[:servicenow_integration]}'"
        else
          if integration['integrationType']['code'] != 'serviceNow'
            raise_command_error "Integration '#{integration['id']}' must be a Service Now integration"
          end
          params['serviceNow'] ||= {}
          params['serviceNow']['integration'] = {'id' => integration['id'].to_i}
        end
      end
      payload.deep_merge!({object_key => params})
    end
    if payload[object_key].empty?
      raise_command_error "Specify at least one option to update.\n#{optparse}"
    end
    @monitoring_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @monitoring_settings_interface.dry.update(payload)
      return
    end
    json_response = @monitoring_settings_interface.update(payload)
    exit_code, err = 0, nil
    render_response(json_response, options, object_key) do
      if json_response['success']
        print_green_success "Updated monitoring settings"
        get([] + (options[:remote] ? ["-r",options[:remote]] : []))
      else
        exit_code, err = 1, "Error updating monitoring settings: #{json_response['msg'] || json_response['errors']}"
        print_rest_errors(json_response)
      end
    end
    return exit_code, err
  end

  private

  def object_key
    'monitoringSettings'
  end

end
