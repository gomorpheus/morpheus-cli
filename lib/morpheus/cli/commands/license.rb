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
        print_h2 "License Usage", [], options
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
      "Stats Reporting" => lambda {|it| format_boolean it["reportStatus"] },
      "Hard Limit" => lambda {|it| format_boolean it["hardLimit"] },
      "Limit Type" => lambda {|it| format_limit_type(it) },
    }

    if license['zoneTypes'] && license['zoneTypes'].size > 0
      description_cols["Included Clouds"] = lambda {|it| it['zoneTypes'].join(', ') }
    elsif license['zoneTypesExcluded'] && license['zoneTypesExcluded'].size > 0
      description_cols["Excluded Clouds"] = lambda {|it| it['zoneTypesExcluded'].join(', ') }
    end
    # if license['limitType'] == 'standard'
    #   # new standard metrics limit
    #   used_vms = current_usage['vms']['count'] rescue nil
    #   used_discovered_vms = current_usage['discoveredVms']['count'] rescue nil
    #   used_hosts = current_usage['hosts']['count'] rescue nil
    #   used_discovered_hosts = current_usage['discoveredHosts']['count'] rescue nil
    #   used_executions = current_usage['executions']['count'] rescue nil
    #   max_vms = license["maxManagedVms"].to_i
    #   max_discovered_vms = license['maxDiscoveredVms'].to_i
    #   max_hosts = license['maxManagedHosts'].to_i
    #   max_discovered_hosts = license['maxDiscoveredHosts'].to_i
    #   max_executions = license['maxExecutions'].to_i
    #   description_cols["VMs"] = lambda {|it| format_limit(max_vms, used_vms) } # if max_vms.to_i > 0
    #   description_cols["Discovered VMs"] = lambda {|it| format_limit(max_discovered_vms, used_discovered_vms) } if max_discovered_vms.to_i > 0
    #   description_cols["Hosts"] = lambda {|it| format_limit(max_hosts, used_hosts)  } if max_hosts.to_i > 0
    #   description_cols["Discovered Hosts"] = lambda {|it| format_limit(max_discovered_hosts, used_discovered_hosts) } if max_discovered_hosts.to_i > 0
    #   description_cols["Executions"] = lambda {|it| format_limit(max_executions, used_executions) } if max_executions.to_i > 0
    # else
    #   # old workloads limit
    #   used_memory = current_usage['memory'] rescue nil
    #   used_storage = current_usage['storage'] rescue nil
    #   used_workloads = current_usage['workloads'] rescue nil
    #   max_memory = license['maxMemory'].to_i
    #   max_storage = license['maxStorage'].to_i
    #   max_workloads = license['maxInstances'].to_i
    #   description_cols["Memory"] = lambda {|it| format_limit(max_memory, used_memory) } if max_memory.to_i > 0
    #   description_cols["Storage"] = lambda {|it| format_limit(max_storage, used_storage) } if max_storage.to_i > 0
    #   description_cols["Workloads"] = lambda {|it| format_limit(max_workloads, used_workloads) } # if max_workloads.to_i > 0
    # end
    print_description_list(description_cols, license)
  end

  def print_license_usage(license, current_usage)
    unlimited_label = "Unlimited"
    # unlimited_label = "∞"
    if license['limitType'] == 'standard'
      # new standard metrics limit
      used_vms = current_usage['vms']['count'] rescue nil
      used_discovered_vms = current_usage['discoveredVms']['count'] rescue nil
      used_hosts = current_usage['hosts']['count'] rescue nil
      used_discovered_hosts = current_usage['discoveredHosts']['count'] rescue nil
      used_executions = current_usage['executions']['count'] rescue nil
      max_vms = license["maxManagedVms"].to_i
      max_vms = 0
      max_discovered_vms = license['maxDiscoveredVms'].to_i
      max_hosts = license['maxManagedHosts'].to_i
      max_discovered_hosts = license['maxDiscoveredHosts'].to_i
      max_executions = license['maxExecutions'].to_i
      label_width = 15
      chart_opts = {max_bars: 20, unlimited_label: '0%', percent_sigdig: 0}
      out = ""
      out << cyan + "VMs".rjust(label_width, ' ') + ": " + generate_usage_bar(used_vms, max_vms, chart_opts) + cyan + used_vms.to_s.rjust(8, ' ') + " / " + (max_vms.to_i > 0 ? max_vms.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Discoverd VMs".rjust(label_width, ' ') + ": " + generate_usage_bar(used_discovered_vms, max_discovered_vms, chart_opts) + cyan + used_discovered_vms.to_s.rjust(8, ' ') + " / " + (max_discovered_vms.to_i > 0 ? max_discovered_vms.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      out << cyan + "Hosts".rjust(label_width, ' ') + ": " + generate_usage_bar(used_hosts, max_hosts, chart_opts) + cyan + used_hosts.to_s.rjust(8, ' ') + " / " + (max_hosts.to_i > 0 ? max_hosts.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      if max_discovered_hosts.to_i > 0
        out << cyan + "Discoverd Hosts".rjust(label_width, ' ') + ": " + generate_usage_bar(used_discovered_hosts, max_discovered_hosts, chart_opts) + cyan + used_discovered_hosts.to_s.rjust(8, ' ') + " / " + (max_discovered_vms.to_i > 0 ? max_discovered_vms.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      else

      end
      out << cyan + "Executions".rjust(label_width, ' ') + ": " + generate_usage_bar(used_executions, max_executions, chart_opts) + cyan + used_executions.to_s.rjust(8, ' ') + " / " + (max_executions.to_i > 0 ? max_executions.to_s : unlimited_label).to_s.ljust(15, ' ') + "\n"
      print out
    else
      # old workloads limit
      used_memory = current_usage['memory'] rescue nil
      used_storage = current_usage['storage'] rescue nil
      used_workloads = current_usage['workloads'] rescue nil
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
end
