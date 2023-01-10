require 'morpheus/cli/cli_command'

class Morpheus::Cli::GuidanceSettings
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'guidance-settings'
  set_command_description "View and manage guidance settings"
  register_subcommands :get, :update

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @guidance_settings_interface = @api_client.guidance_settings
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
      opts.footer = "Get guidance settings."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    params.merge!(parse_query_options(options))
    @guidance_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @guidance_settings_interface.dry.get(options)
      return
    end
    json_response = @guidance_settings_interface.get(options)
    render_response(json_response, options, object_key) do
      guidance_settings = json_response[object_key]
      print_h1 "Guidance Settings", options
      print_h2 "Power Settings", options.merge(:border_style => :thin)
      #Power shutdown will be suggested when all of the following baseline thresholds are exceeded for a resource
      print_description_list({
        "Average CPU (%)" => lambda {|it| it['cpuAvgCutoffPower'] }, # #Lower limit for average CPU usage
        "Maximum CPU (%)" => lambda {|it| it['cpuMaxCutoffPower'] }, #Lower limit for peak CPU usage
        "Network threshold (bytes)" => lambda {|it| it['networkCutoffPower'] }, #Lower limit for average network bandwidth
      }, guidance_settings, options)
      #print reset, "\n"

      print_h2 "CPU Up-size Settings", options.merge(:border_style => :thin)
      #Up-size will be suggested when all of the following baseline thresholds are exceeded for a resource
      print_description_list({
        "Average CPU (%)" => lambda {|it| it['cpuUpAvgStandardCutoffRightSize'] }, #Upper limit for CPU usage
        "Maximum CPU (%)" => lambda {|it| it['cpuUpMaxStandardCutoffRightSize'] }, #Upper limit for peak CPU usage
      }, guidance_settings, options)
      #print reset, "\n"
    
      print_h2 "Memory Up-size Settings", options.merge(:border_style => :thin)
      #Up-size is suggested when all of the following baseline thresholds are exceeded for a resource
      print_description_list({
        "Minimum Free Memory (%)" => lambda {|it| it['memoryUpAvgStandardCutoffRightSize'] }, #Lower limit for average free memory usage
      }, guidance_settings, options)
      #print reset, "\n"

      print_h2 "Memory Down-size Settings", options.merge(:border_style => :thin)
      #Down-size is suggested when all of the following baseline thresholds are exceeded for a resource
      print_description_list({
        #Upper limit for average free memory
        "Average Free Memory (%)" => lambda {|it| it['memoryDownAvgStandardCutoffRightSize'] },
        #Upper limit for peak memory usage
        "Maximum Free Memory (%)" => lambda {|it| it['memoryDownMaxStandardCutoffRightSize'] },
      }, guidance_settings, options)
      print reset, "\n"
    end
    return 0, nil
  end

  def update(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      opts.on('--power-cpu-avg PERCENT', String, "Power Shutdown Average CPU (%). Lower limit for average CPU usage") do |val|
        params['cpuAvgCutoffPower'] = val.to_i
      end
      opts.on('--power-cpu-max PERCENT', String, "Power Shutdown Maximum CPU (%). Lower limit for peak CPU usage") do |val|
        params['cpuMaxCutoffPower'] = val.to_i
      end
      opts.on('--power-network BYTES', String, "Power Shutdown Network threshold (bytes). Lower limit for average network bandwidth") do |val|
        params['networkCutoffPower'] = val.to_i
      end
      opts.on('--cpu-up-avg PERCENT', String, "CPU Up-size Average CPU (%). Upper limit for CPU usage") do |val|
        params['cpuUpAvgStandardCutoffRightSize'] = val.to_i
      end
      opts.on('--cpu-up-max PERCENT', String, "CPU Up-size Maximum CPU (%). Upper limit for peak CPU usage") do |val|
        params['cpuUpMaxStandardCutoffRightSize'] = val.to_i
      end
      opts.on('--memory-up-avg PERCENT', String, "Memory Up-size Minimum Free Memory (%). Lower limit for average free memory usage") do |val|
        params['memoryUpAvgStandardCutoffRightSize'] = val.to_i
      end
      opts.on('--memory-down-avg PERCENT', String, "Memory Down-size Maximum Free Memory (%). Upper limit for average free memory") do |val|
        params['memoryDownAvgStandardCutoffRightSize'] = val.to_i
      end
      opts.on('--memory-down-max PERCENT', String, "Memory Down-size Maximum Free Memory (%). Upper limit for peak memory usage") do |val|
        params['memoryDownMaxStandardCutoffRightSize'] = val.to_i
      end
      build_standard_update_options(opts, options)
      opts.footer = "Update guidance settings."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    payload = parse_payload(options)
    if !payload
      payload = {}
      payload.deep_merge!({object_key => parse_passed_options(options)}) # inject options passed with -O foo=bar
      payload.deep_merge!({object_key => params}) # inject options --foo bar
    end
    if payload[object_key].empty?
      raise_command_error "Specify at least one option to update.\n#{optparse}"
    end
    @guidance_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @guidance_settings_interface.dry.update(payload)
      return
    end
    json_response = @guidance_settings_interface.update(payload)
    exit_code, err = 0, nil
    render_response(json_response, options, object_key) do
      if json_response['success']
        print_green_success "Updated guidance settings"
        get([] + (options[:remote] ? ["-r",options[:remote]] : []))
      else
        exit_code, err = 1, "Error updating guidance settings: #{json_response['msg'] || json_response['errors']}"
        print_rest_errors(json_response)
      end
    end
    return exit_code, err
  end

  private

  def object_key
    'guidanceSettings'
  end

end
