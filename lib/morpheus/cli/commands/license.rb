require 'morpheus/cli/cli_command'

class Morpheus::Cli::License
  include Morpheus::Cli::CliCommand

  register_subcommands :get, :install, :uninstall, :test
  # deprecated
  register_subcommands :decode, :apply

  set_subcommands_hidden :decode, :apply
  
  #alias_subcommand :details, :get

  def initialize() 
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @license_interface = @api_client.license
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :yaml, :fields, :dry_run, :remote])
      opts.footer = "Get details about the currently installed license.\n" +
                    "This information includes license features and limits.\n" +
                    "The actual secret license key value will never be returned."
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    
    # make api request
    @license_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @license_interface.dry.get()
      return 0, nil
    end
    json_response = @license_interface.get()
    render_response(json_response, options) do
      license = json_response['license']
      current_usage = json_response['currentUsage'] || {}
      print_h1 "License"
      if license.nil?
        print "#{yellow}No license currently installed#{reset}\n\n"
      else
        print_license_details(json_response)
        print_h2 "Current Usage", [], options
        print_license_usage(license, current_usage)
        print reset,"\n"
      end
    end
  end

  def apply(args)
    print_error "#{yellow}DEPRECATION WARNING: `license apply` has been deprecated and replaced with `license install`. Please use `license install` instead.#{reset}\n"
    install(args)
  end

  def install(args)
    options = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Install a new license key.\n" +
                    "This will potentially change the enabled features and capabilities of your appliance."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      if args[0]
        key = args[0]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true}], options[:options])
        key = v_prompt['licenseKey'] || ''
      end
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.install(key)
        return 0
      end
      json_response = @license_interface.install(key)
      license = json_response['license']
      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        print_green_success "License installed!"
        get([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

  def decode(args)
    print_error "#{yellow}DEPRECATION WARNING: `license decode` has been deprecated and replaced with `license test`. Please use `license test` instead.#{reset}\n"
    test(args)
  end

  def test(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Test a license key.\n" +
                    "This is a way to decode and view a license key before installing it."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    key = nil
    if args[0]
      key = args[0]
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true}], options[:options])
      key = v_prompt['licenseKey'] || ''
    end
    begin
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.test(key)
        return
      end
      json_response = @license_interface.test(key)
      license = json_response['license']
      current_usage = json_response['currentUsage'] || {}
      exit_code, err = 0, nil
      if license.nil?
        err = "Unable to decode license."
        exit_code = 1
        #return err, exit_code
      end
      render_result = render_with_format(json_response, options)
      if render_result
        return exit_code, err
      end
      if options[:quiet]
        return exit_code, err
      end
      if exit_code != 0
        print_error red, err.to_s, reset, "\n"
        return exit_code, err
      end
      
      # all good
      print_h1 "License"
      print_license_details(json_response)
      print_h2 "License Usage", [], options
      print_license_usage(license, current_usage)
      print reset,"\n"
      return exit_code, err
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def uninstall(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:auto_confirm, :json, :yaml, :dry_run, :remote])
      opts.footer = "Uninstall the current license key.\n" +
                    "This clears out the current license key from the appliance.\n" +
                    "The function of the remote appliance will be restricted without a license installed.\n" +
                    "Be careful using this."
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.uninstall(params)
        return
      end
      
      unless options[:quiet]
        print cyan,"#{bold}WARNING!#{reset}#{cyan} You are about to uninstall your license key.",reset,"\n"
        print yellow, "Be careful using this. Make sure you have a copy of your key somewhere if you intend to use it again.",reset, "\n"
        print "\n"
      end
      
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you want to uninstall the license key for remote #{@appliance_name} - #{@appliance_url}?")
        return 9, "command aborted"
      end

      json_response = @license_interface.uninstall(params)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      return 0 if options[:quiet]
      print_green_success "License uninstalled!"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def format_product_tier(license)
    product_tier = license['productTier'] || 'capacity'
    if product_tier == 'capacity'
      'Capacity'
    elsif product_tier == 'essentials'
      'Essentials'
    elsif product_tier == 'pro'
      'Pro'
    elsif product_tier == 'enterprise'
      'Enterprise'
    elsif product_tier == 'msp'
      'Service Provider'
    else
      product_tier.to_s.capitalize
    end
  end

  def format_limit_type(license)
    limit_type = license['limitType'] || 'workload'
    if limit_type == 'standard' || limit_type == 'metrics'
      'Standard'
    else
      limit_type.to_s.capitalize
    end
  end

  def format_limit(max, used)
    formatted_max = max.to_i > 0 ? format_number(max) : "Unlimited"
    if used
      formatted_used = format_number(used)
      "#{formatted_used} / #{formatted_max}"
    else
      "#{formatted_max}"
    end
  end

  def format_limit_bytes(max, used)
    formatted_max = max.to_i > 0 ? format_bytes(max) : "Unlimited"
    if used
      formatted_used = format_bytes(used)
      "#{formatted_used} / #{formatted_max}"
    else
      "#{formatted_max}"
    end
  end

  def print_license_details(json_response)
    license = json_response['license']
    current_usage = json_response['currentUsage'] || {}
    description_cols = {
      "Account" => 'accountName',
      "Product Tier" => lambda {|it| format_product_tier(it) },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| 
        if it['endDate']
          format_local_dt(it['endDate']).to_s + ' (' + format_duration(Time.now, it['endDate']).to_s + ')' 
        else
          'Never'
        end
      },
      "Multi-Tenant" => lambda {|it| format_boolean it["multiTenant"] },
      "White Label" => lambda {|it| format_boolean it["whitelabel"] },
      "Stats Reporting" => lambda {|it| format_boolean it["reportStatus"] },
      "Hard Limit" => lambda {|it| format_boolean it["hardLimit"] },
      "Limit Type" => lambda {|it| format_limit_type(it) },
    }

    description_cols.delete("Multi-Tenant") if !license['multiTenant']
    description_cols.delete("White Label") if !license['whitelabel']

    if license['zoneTypes'] && license['zoneTypes'].size > 0
      description_cols["Included Clouds"] = lambda {|it| it['zoneTypes'].join(', ') }
    elsif license['zoneTypesExcluded'] && license['zoneTypesExcluded'].size > 0
      description_cols["Excluded Clouds"] = lambda {|it| it['zoneTypesExcluded'].join(', ') }
    end
    print_description_list(description_cols, license)
  end

  def print_license_usage(license, current_usage)
    unlimited_label = "Unlimited"
    # unlimited_label = "∞"
    if license['limitType'] == 'standard'
      # new standard metrics limit
      used_managed_servers = current_usage['managedServers']
      used_discovered_servers = current_usage['discoveredServers']
      used_hosts = current_usage['hosts']
      used_mvm = current_usage['mvm']
      used_sockets = current_usage['sockets']
      used_iac = current_usage['iac']
      used_xaas = current_usage['xaas']
      used_executions = current_usage['executions']
      used_distributed_workers = current_usage['distributedWorkers']
      used_discovered_objects = current_usage['discoveredObjects']


      max_managed_servers = license["maxManagedServers"]
      max_discovered_servers = license['maxDiscoveredServers']
      max_hosts = license['maxHosts']
      max_mvm = license['maxMvm']
      max_sockets = license['maxSockets']
      max_iac = license['maxIac']
      max_xaas = license['maxXaas']
      max_executions = license['maxExecutions']
      max_distributed_workers = license['maxDistributedWorkers']
      max_discovered_objects = license['maxDiscoveredObjects']
      label_width = 20
      chart_opts = {max_bars: 20, unlimited_label: '0%', percent_sigdig: 0}
      out = ""
      out << cyan + "Managed Servers".rjust(label_width, ' ') + ": " + generate_usage_bar(used_managed_servers, max_managed_servers, chart_opts) + cyan + used_managed_servers.to_s.rjust(8, ' ') + " / " + (max_managed_servers ? max_managed_servers.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Discovered Servers".rjust(label_width, ' ') + ": " + generate_usage_bar(used_discovered_servers, max_discovered_servers, chart_opts) + cyan + used_discovered_servers.to_s.rjust(8, ' ') + " / " + (max_discovered_servers ? max_discovered_servers.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Hosts".rjust(label_width, ' ') + ": " + generate_usage_bar(used_hosts, max_hosts, chart_opts) + cyan + used_hosts.to_s.rjust(8, ' ') + " / " + (max_hosts ? max_hosts.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "MVM Hosts".rjust(label_width, ' ') + ": " + generate_usage_bar(used_mvm, max_mvm, chart_opts) + cyan + used_mvm.to_s.rjust(8, ' ') + " / " + (max_mvm ? max_mvm.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Sockets".rjust(label_width, ' ') + ": " + generate_usage_bar(used_sockets, max_sockets, chart_opts) + cyan + used_sockets.to_s.rjust(8, ' ') + " / " + (max_sockets ? max_sockets.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Iac Deployments".rjust(label_width, ' ') + ": " + generate_usage_bar(used_iac, max_iac, chart_opts) + cyan + used_iac.to_s.rjust(8, ' ') + " / " + (max_iac ? max_iac.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Xaas Instances".rjust(label_width, ' ') + ": " + generate_usage_bar(used_xaas, max_xaas, chart_opts) + cyan + used_xaas.to_s.rjust(8, ' ') + " / " + (max_xaas ? max_xaas.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Executions".rjust(label_width, ' ') + ": " + generate_usage_bar(used_executions, max_executions, chart_opts) + cyan + used_executions.to_s.rjust(8, ' ') + " / " + (max_executions ? max_executions.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Distributed Workers".rjust(label_width, ' ') + ": " + generate_usage_bar(used_distributed_workers, max_distributed_workers, chart_opts) + cyan + used_distributed_workers.to_s.rjust(8, ' ') + " / " + (max_distributed_workers ? max_distributed_workers.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      #out << cyan + "Discovered Objects".rjust(label_width, ' ') + ": " + generate_usage_bar(used_discovered_objects, max_discovered_objects, chart_opts) + cyan + used_discovered_objects.to_s.rjust(8, ' ') + " / " + (max_discovered_objects.to_i > 0 ? max_discovered_objects.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      print out
    else
      # old workloads limit
      used_memory = current_usage['memory']
      used_storage = current_usage['storage']
      used_workloads = current_usage['workloads']
      max_memory = license['maxMemory'].to_i
      max_storage = license['maxStorage'].to_i
      max_workloads = license['maxInstances'].to_i
      label_width = 15
      chart_opts = {max_bars: 20, unlimited_label: '0%', percent_sigdig: 0}
      out = ""
      out << cyan + "Workloads".rjust(label_width, ' ') + ": " + generate_usage_bar(used_workloads, max_workloads, chart_opts) + cyan + used_workloads.to_s.rjust(15, ' ') + " / " + (max_workloads.to_i > 0 ? max_workloads.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Memory".rjust(label_width, ' ') + ": " + generate_usage_bar(used_memory, max_memory, chart_opts) + cyan + Filesize.from("#{used_memory} B").pretty.strip.rjust(15, ' ') + " / " + (max_memory.to_i > 0 ? Filesize.from("#{max_memory} B").pretty : unlimited_label).strip.ljust(15, ' ') + "\n"
      out << cyan + "Storage".rjust(label_width, ' ') + ": " + generate_usage_bar(used_storage, max_storage, chart_opts) + cyan + Filesize.from("#{used_storage} B").pretty.strip.rjust(15, ' ') + " / " + (max_storage.to_i > 0 ? Filesize.from("#{max_storage} B").pretty : unlimited_label).strip.ljust(15, ' ') + "\n"
      print out
    end
  end

  # todo: use this to dry print_license_usage
  def format_limit(label, used, max, opts={})
    unlimited_label = "Unlimited"
    # unlimited_label = "∞"
    label_width = opts[:label_width] || 15
    chart_opts = {max_bars: 20, unlimited_label: '0%', percent_sigdig: 0}
    chart_opts.merge!(opts[:chart_opts]) if opts[:chart_opts]
    cyan + label.rjust(label_width, ' ') + ": " + generate_usage_bar(used, max, chart_opts) + cyan + used.to_s.rjust(label_width, ' ') + " / " + (max.to_i > 0 ? max.to_s : unlimited_label).to_s.ljust(label_width, ' ') + "\n"
  end


end
