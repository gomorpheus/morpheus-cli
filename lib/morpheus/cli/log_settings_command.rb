require 'morpheus/cli/cli_command'

class Morpheus::Cli::LogSettingsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  set_command_hidden
  set_command_name :'log-settings'

  register_subcommands :get, :update
  register_subcommands :enable_integration, :disable_integration
  register_subcommands :add_syslog_rule, :remove_syslog_rule
  
  set_default_subcommand :get

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @log_settings_interface = @api_client.log_settings
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get log settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    
    begin
      @log_settings_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @log_settings_interface.dry.get()
        return
      end
      json_response = @log_settings_interface.get()
      if options[:json]
        puts as_json(json_response, options, "logSettings")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "logSettings")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['logSettings']], options)
        return 0
      end

      log_settings = json_response['logSettings']

      print_h1 "Log Settings"
      print cyan
      description_cols = {
        "Logs Enabled" => lambda {|it| format_boolean(it['enabled']) },
        "Availability Time Frame" => lambda {|it| it['retentionDays'] }
      }
      print_description_list(description_cols, log_settings)

      # Syslog Forwarding Rules
      if !log_settings['syslogRules'].empty?
        print_h2 "Syslog Forwarding Rules"
        print cyan
        print as_pretty_table(log_settings['syslogRules'], [:id, :name, :rule])
      end

      # Integrations
      if !log_settings['integrations'].empty?
        print_h2 "Integrations"
        print cyan
        print as_pretty_table(log_settings['integrations'], [:name, :enabled, :host, :port])
      end
      print reset "\n"
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
      opts.on("--enabled [on|off]", ['on','off'], "Logs enabled") do |val|
        params['enabled'] = ['true','on'].include?(val.to_s.strip)
      end
      opts.on("-R", "--retention NUMBER", Integer, "Availability time frame in days") do |val|
        params['retentionDays'] = val.to_i
      end
      opts.on("-s", "--syslog JSON", String, "Syslog rules JSON") do |val|
        begin
          syslog_rules = JSON.parse(val.to_s)
          options[:syslogRules] = syslog_rules.kind_of?(Array) ? syslog_rules : [syslog_rules]
        rescue JSON::ParserError => e
          print_red_alert "Unable to parse syslog rules JSON"
          exit 1
        end
      end
      opts.on('--syslog-list LIST', Array, "Syslog rules list in form of name value pairs: name1=rule1,name2=rule2") do |val|
        options[:syslogRules] = val.collect { |nv|
          parts = nv.split('=')
          {'name' => parts[0].strip, 'rule' => (parts.count > 1 ? parts[1].strip : '')}
        }
      end
      opts.on( '-i', '--integrations JSON', "Integrations") do |val|
        begin
          ints = JSON.parse(val.to_s)
          options[:integrations] = ints.kind_of?(Array) ? ints : [ints]
        rescue JSON::ParserError => e
          print_red_alert "Unable to parse integrations JSON"
          exit 1
        end
      end
      build_common_options(opts, options, [:json, :payload, :dry_run, :quiet, :remote])
      opts.footer = "Update your log settings."
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
        payload = {'logSettings' => params}

        if !options[:syslogRules].nil?
          if options[:syslogRules].reject { |rule| rule['name'] }.count > 0
            print_red_alert "Invalid forwarding rule(s), name is required"
            return 1
          end
          payload['logSettings']['syslogRules'] = options[:syslogRules]
        end

        if !options[:integrations].nil?
          if options[:integrations].reject { |rule| rule['name'] && rule['host'] && rule['port'] }.count > 0
            print_red_alert "Invalid integration: name, host and port are required"
            return 1
          end
          payload['logSettings']['integrations'] = options[:integrations]
        end
      end

      if payload['logSettings'].empty?
        print_green_success "Nothing to update"
        exit 1
      end

      @log_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @log_settings_interface.dry.update(payload)
        return
      end
      json_response = @log_settings_interface.update(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Updated log settings"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error updating log settings: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def enable_integration(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[name] [host] [port]")
      build_common_options(opts, options, [:json, :payload, :dry_run, :quiet, :remote])
      opts.footer = "Enables specifed integration.\n" +
          "[name] is required. Currently supports splunk and logrhythm integrations.\n" +
          "[host] is required. Host of the integration.\n" +
          "[port] is required. Port of the integration."
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 3
      raise_command_error "wrong number of arguments, expected 3 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    if !args[2].to_i
      raise_command_error "port argument must be a number"
    end

    begin
      payload = parse_payload(options)

      if !payload
        payload = {'integration' => {'enabled' => true, 'host' => args[1], 'port' => args[2]}}
      end

      @log_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @log_settings_interface.dry.update_integration(args[0], payload)
        return
      end
      json_response = @log_settings_interface.update_integration(args[0], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Integration added"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error enabling integration: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def disable_integration(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Disabled specifed integration.\n" +
          "[name] is required. Currently supports splunk and logrhythm integrations."
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = {'integration' => {'enabled' => false}}

      @log_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @log_settings_interface.dry.update_integration(args[0], payload)
        return
      end
      json_response = @log_settings_interface.update_integration(args[0], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Integration removed"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error disabling integration: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_syslog_rule(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[name] [rule]")
      build_common_options(opts, options, [:json, :payload, :dry_run, :quiet, :remote])
      opts.footer = "Add syslog rule.\n" +
          "[name] is required. If syslog already exists, the specified rule will be updated\n" +
          "[rule] is required"
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)

      if !payload
        payload = {'syslogRule' => {'name' => args[0], 'rule' => args[1]}}
      end

      @log_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @log_settings_interface.dry.add_syslog_rule(payload)
        return
      end
      json_response = @log_settings_interface.add_syslog_rule(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Syslog rule added"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error adding syslog rule: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_syslog_rule(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[syslog-rule]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a syslog rule.\n" +
          "[syslog-rule] is required. This is the name or id of an syslog rule."
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      syslog_rule = find_syslog_rule_by_name_or_id(args[0])

      if syslog_rule.nil?
        print_red_alert "Syslog rule not found for: #{args[0]}"
        return 1
      end

      @log_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @log_settings_interface.dry.destroy_syslog_rule(syslog_rule['id'])
        return
      end
      json_response = @log_settings_interface.destroy_syslog_rule(syslog_rule['id'])

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Syslog rule removed"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error removing syslog rule: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_syslog_rule_by_name_or_id(val)
    log_settings = @log_settings_interface.get()['logSettings']
    log_settings['syslogRules'].find do |rule|
      val.casecmp(rule['name']) == 0 || rule['id'] == val.to_i
    end
  end

end
