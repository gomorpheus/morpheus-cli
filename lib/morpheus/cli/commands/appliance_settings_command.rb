require 'morpheus/cli/cli_command'

class Morpheus::Cli::ApplianceSettingsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'appliance-settings'

  register_subcommands :get, :update, :toggle_maintenance, :'reindex'
  
  set_default_subcommand :get

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @appliance_settings_interface = @api_client.appliance_settings
    @roles_interface = @api_client.roles
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get appliance settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    
    begin
      @appliance_settings_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @appliance_settings_interface.dry.get()
        return
      end
      json_response = @appliance_settings_interface.get()
      if options[:json]
        puts as_json(json_response, options, "applianceSettings")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "applianceSettings")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['applianceSettings']], options)
        return 0
      end

      appliance_settings = json_response['applianceSettings']

      print_h1 "Appliance Settings"
      print cyan
      description_cols = {
        "Appliance URL" => lambda {|it| it['applianceUrl'] },
        "Internal Appliance URL (PXE)" => lambda {|it| it['internalApplianceUrl'] },
        "API Allowed Origins" => lambda {|it| it['apiAllowedOrigins'] },
        # Tenant Management Settings
        "Registration Enabled" => lambda {|it| format_boolean(it['registrationEnabled']) },
        "Default Tenant Role" => lambda {|it| it['defaultRoleId'] },
        "Default User Role" => lambda {|it| it['defaultUserRoleId'] },
        "Docker Privileged Mode" => lambda {|it| format_boolean(it['dockerPrivilegedMode']) },
        # User Management Settings
        "Expire Password After" => lambda {|it| format_days(it['expirePwdDays']) },
        "Disable User After Attempts" => lambda {|it| it['disableAfterAttempts'] == 0 ? 'Disabled' : it['disableAfterAttempts']},
        "Disable User if Inactive For" => lambda {|it| format_days(it['disableAfterDaysInactive']) },
        "Send warning email before deactivating" => lambda {|it| format_days(it['warnUserDaysBefore']) },
        # Email Settings
        "SMTP From Address" => lambda {|it| it['smtpMailFrom'] },
        "SMTP Server" => lambda {|it| it['smtpServer'] },
        "SMTP Port" => lambda {|it| it['smtpPort'] },
        "SMTP SSL Enabled" => lambda {|it| format_boolean(it['smtpSSL']) },
        "SMTP TLS Encryption" => lambda {|it| format_boolean(it['smtpTLS']) },
        "SMTP User" => lambda {|it| it['smtpUser'] },
        "SMTP Password" => lambda {|it| it['smtpPassword'] },
        # Proxy Settings
        "Proxy Host" => lambda {|it| it['proxyHost'] },
        "Proxy Port" => lambda {|it| it['proxyPort'] },
        "Proxy User" => lambda {|it| it['proxyUser'] },
        "Proxy Password" => lambda {|it| it['proxyPassword'] },
        "Proxy Domain" => lambda {|it| it['proxyDomain'] },
        "Proxy Workstation" => lambda {|it| it['proxyWorkstation'] },
        # Currency Settings
        "Currency Provider" => lambda {|it| it['currencyProvider'] },
        "Currency Provider API Key" => lambda {|it| it['currencyKey'] },
        # Retention Settings
        "Stats Retainment Period" => lambda {|it| it['statsRetainmentPeriod'] ? it['statsRetainmentPeriod'].to_s + ' days' : '' },
      }
      print_description_list(description_cols, appliance_settings)

      enabled_zone_types = appliance_settings['enabledZoneTypes']

      if enabled_zone_types.nil? || enabled_zone_types.empty?
        print_h2 "Enabled Clouds"
        print cyan
        print yellow "No Clouds Enabled"
      else
        print_h2 "Enabled Clouds"
        print cyan
        print enabled_zone_types.collect {|it| it['name']}.join(', ')
      end
      print reset, "\n"
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
      opts.banner = opts.banner = subcommand_usage()
      opts.on("--appliance-url STRING", String, "Appliance URL") do |val|
        params['applianceUrl'] = val == 'null' ? nil : val
      end
      opts.on("--internal-appliance-url STRING", String, "Internal appliance URL (PXE)") do |val|
        params['internalApplianceUrl'] = val == 'null' ? nil : val
      end
      opts.on("--api-allowed-origins STRING", String, "API allowed origins") do |val|
        params['corsAllowed'] = val == 'null' ? nil : val
      end
      opts.on("--registration-enabled [on|off]", ['on','off'], "Tenant registration enabled") do |val|
        params['registrationEnabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--default-tenant-role ROLE", String, "Default tenant role authority or ID") do |val|
        if val == 'null'
          params['defaultRoleId'] = nil
        else
          options[:defaultTenantRole] = val
        end
      end
      opts.on("--default-user-role ROLE", String, "Default user role authority or ID") do |val|
        if val == 'null'
          params['defaultUserRoleId'] = nil
        else
          options[:defaultUserRole] = val
        end
      end
      opts.on("--docker-privileged-mode [on|off]", ['on','off'], "Docker privileged mode") do |val|
        params['dockerPrivilegedMode'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--expire-pwd-days NUMBER", Integer, "Expire password after specified days. Set to 0 to disable this feature") do |val|
        params['expirePwdDays'] = val.to_i
      end
      opts.on("--disable-after-attempts NUMBER", Integer, "Disable user after attempts. Set to 0 to disable this feature") do |val|
        params['disableAfterAttempts'] = val.to_i
      end
      opts.on("--disable-after-days-inactive NUMBER", Integer, "Disable user if inactive for specified days. Set to 0 to disable this feature") do |val|
        params['disableAfterDaysInactive'] = val.to_i
      end
      opts.on("--warn-user-days-before NUMBER", Integer, "Send warning email before deactivating. Set to 0 to disable this feature") do |val|
        params['warnUserDaysBefore'] = val.to_i
      end
      opts.on("--smtp-from-email STRING", String, "From email address") do |val|
        params['smtpMailFrom'] = val == 'null' ? nil : val
      end
      opts.on("--smtp-server STRING", String, "SMTP server / host") do |val|
        params['smtpServer'] = val == 'null' ? nil : val
      end
      opts.on("--smtp-port NUMBER", String, "SMTP port") do |val|
        params['smtpPort'] = val == 'null' ? nil : val.to_i
      end
      opts.on("--smtp-ssl [on|off]", ['on','off'], "Use SSL for SMTP connections") do |val|
        params['smtpSSL'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--smtp-tls [on|off]", ['on','off'], "Use TLS for SMTP connections") do |val|
        params['smtpTLS'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--smtp-user STRING", String, "SMTP user") do |val|
        params['smtpUser'] = val == 'null' ? nil : val
      end
      opts.on("--smtp-password STRING", String, "SMTP password") do |val|
        params['smtpPassword'] = val == 'null' ? nil : val
      end
      opts.on("--proxy-host STRING", String, "Proxy host") do |val|
        params['proxyHost'] = val == 'null' ? nil : val
      end
      opts.on("--proxy-port NUMBER", String, "Proxy port") do |val|
        params['proxyPort'] = val == 'null' ? nil : val.to_i
      end
      opts.on("--proxy-user STRING", String, "Proxy user") do |val|
        params['proxyUser'] = val == 'null' ? nil : val
      end
      opts.on("--proxy-password STRING", String, "Proxy password") do |val|
        params['proxyPassword'] = val == 'null' ? nil : val
      end
      opts.on("--proxy-domain STRING", String, "Proxy domain") do |val|
        params['proxyDomain'] = val == 'null' ? nil : val
      end
      opts.on("--proxy-workstation STRING", String, "Proxy workstation") do |val|
        params['proxyWorkstation'] = val == 'null' ? nil : val
      end
      opts.on("--currency-provider STRING", String, "Currency provider") do |val|
        params['currencyProvider'] = val == 'null' ? nil : val
      end
      opts.on("--currency-key STRING", String, "Currency provider API key") do |val|
        params['currencyKey'] = val == 'null' ? nil : val
      end
      opts.on("--enable-all-clouds", "Set all cloud types enabled status on, can be used in conjunction with --disable-clouds") do
        params['enableAllZoneTypes'] = true
      end
      opts.on("--enable-clouds LIST", Array, "List of cloud types to set enabled status on, each item can be either name or ID") do |list|
        options[:enableZoneTypes] = list
      end
      opts.on("--disable-clouds LIST", Array, "List of cloud types to set enabled status off, each item can be either name or ID") do |list|
        options[:disableZoneTypes] = list
      end
      opts.on("--disable-all-clouds", "Set all cloud types enabled status off, can be used in conjunction with --enable-clouds options") do
        params['disableAllZoneTypes'] = true
      end
      opts.on("--stats-retainment-period DAYS", Integer, "Stats retainment period. The number of days stats should be available. Can be 30, 60, or 90.") do |val|
        params['statsRetainmentPeriod'] = val.to_i
      end
      build_common_options(opts, options, [:json, :payload, :dry_run, :quiet, :remote])
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)

      if !payload
        available_zone_types = @appliance_settings_interface.cloud_types['zoneTypes']

        if options[:enableZoneTypes]
          params['enableZoneTypes'] = options[:enableZoneTypes].collect do |zone_type_id|
            zone_type = available_zone_types.find { |it| it['id'] == zone_type_id || it['id'].to_s == zone_type_id || it['name'] == zone_type_id }
            if zone_type.nil?
              print_red_alert "Cloud type #{zone_type_id} not found"
              exit 1
            end
            zone_type['id']
          end
        end
        if options[:disableZoneTypes]
          params['disableZoneTypes'] = options[:disableZoneTypes].collect do |zone_type_id|
            zone_type = available_zone_types.find { |it| it['id'] == zone_type_id || it['id'].to_s == zone_type_id || it['name'] == zone_type_id }
            if zone_type.nil?
              print_red_alert "Cloud type #{zone_type_id} not found"
              exit 1
            end
            zone_type['id']
          end
        end

        if options[:defaultTenantRole]
          role = find_role_by_name_or_id(nil, options[:defaultTenantRole])
          if role.nil?
            exit 1
          end
          params['defaultRoleId'] = role['id']
        end

        if options[:defaultUserRole]
          role = find_role_by_name_or_id(nil, options[:defaultUserRole])
          if role.nil?
            print_red_alert "Default user role #{options[:defaultUserRole]} not found"
            exit 1
          end
          params['defaultUserRoleId'] = role['id']
        end

        if params['currencyProvider']
          currency_providers = @api_client.options.options_for_source('currencyProviders')['data']
          currency_provider = currency_providers.find {|it| it['name'] == params['currencyProvider'] || it['value'] == params['currencyProvider']}

          if currency_provider.nil?
            print_red_alert "Invalid currency provider #{params['currencyProvider']}, valid options: #{currency_providers.collect {|it| it['value']}.join('|')}"
            exit 1
          end
        end

        payload = {'applianceSettings' => params}
      end

      @appliance_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @appliance_settings_interface.dry.update(payload)
        return
      end
      json_response = @appliance_settings_interface.update(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Updated appliance settings"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error updating appliance settings: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def toggle_maintenance(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      opts.on("--enabled [on|off]", String, "Enabled (on) or Disabled (off)") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_standard_update_options(opts, options, [:auto_confirm], [:payload, :options])
      opts.footer = "Toggle maintenance mode."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    if params['enabled'].nil?
      confirm!("Are you sure you would like to toggle maintenance mode?", options)
    else
      confirm!("Are you sure you would like to toggle maintenance mode: #{params['enabled'] ? 'on' : 'off'}?", options)
    end
    @appliance_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @appliance_settings_interface.dry.maintenance(params)
      return
    end
    json_response = @appliance_settings_interface.maintenance(params)
    render_response(json_response, options) do
      print_green_success "Toggled maintenance mode: '#{params['enabled'] ? 'on' : 'off'}'"
    end
    return 0, nil
  end

  def reindex(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      build_standard_update_options(opts, options, [:auto_confirm], [:payload, :options])
      opts.footer = "Reindex all search data."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    confirm!("Are you sure you would like reindex all search data?", options)
    @appliance_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @appliance_settings_interface.dry.reindex(params)
      return
    end
    json_response = @appliance_settings_interface.reindex(params)
    render_response(json_response, options) do
      print_green_success "Reindexing all search data..."
    end
    return 0, nil
  end

  private

  def format_days(days)
    days ? (days == 0 ? 'Disabled' : days + ' Days') : ''
  end
end
