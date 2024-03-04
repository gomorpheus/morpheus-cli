require 'morpheus/cli/cli_command'

class Morpheus::Cli::Hub
  include Morpheus::Cli::CliCommand

  set_command_description "View hub config and usage metrics."
  set_command_name :'hub'
  register_subcommands :get, {:usage => :usage_data}, :checkin, :register
  
  # this is a hidden utility command
  set_command_hidden

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)   
    @hub_interface = @api_client.hub
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = "View hub configuration."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    params.merge!(parse_query_options(options))
    # execute api request
    @hub_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @hub_interface.dry.get(params)
      return
    end
    json_response = @hub_interface.get(params)
    # render response
    render_response(json_response, options) do
      print_h1 "Morpheus Hub Config", [], options
      print_description_list({
        "Hub URL" => lambda {|it| it['hub']['url'] },
        "Appliance ID" => lambda {|it| it['hub']['applianceUniqueId'] },
        "Registered" => lambda {|it| format_boolean(it['hub']['registered']) },
        "Stats Reporting" => lambda {|it| format_boolean(it['hub']['reportStatus']) },
        "Send Data" => lambda {|it| format_boolean(it['hub']['sendData']) },
      }, json_response, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def usage_data(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = "View appliance usage data that is sent to the hub."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    params.merge!(parse_query_options(options))
    # execute api request
    @hub_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @hub_interface.dry.usage(params)
      return
    end
    json_response = @hub_interface.usage(params)
    # render response
    render_response(json_response, options) do
      usage_data = json_response['data']
      print_h1 "Morpheus Hub Usage", [], options
      print_hub_usage_data_details(json_response, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def checkin(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( nil, '--asynchronous', "Execute the checkin asynchronously" ) do
        params[:async] = true
      end
      build_standard_post_options(opts, options)
      opts.footer = <<-EOT
Checkin with the hub.
This sends the current appliance usage data to the hub and
it is only done if the appliance is registered with the hub
and the appliance license has Stats Reporting enabled.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    payload = parse_payload(options)
    # execute api request
    @hub_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @hub_interface.dry.checkin(payload, params)
      return
    end
    json_response = @hub_interface.checkin(payload, params)
    render_response(json_response, options) do
      msg = json_response["msg"] || "Hub checkin complete"
      print_green_success msg
    end
  end

  def register(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-f', '--force', "Force registration" ) do
        params[:force] = true
      end
      build_standard_post_options(opts, options)
      opts.footer = <<-EOT
Register appliance with the hub to get a unique id for the appliance to checkin with.
The registration is skipped if the appliance is already registered.
The --force option can be used to execute this even if it is already registered.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    payload = parse_payload(options)
    # execute api request
    @hub_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @hub_interface.dry.register(payload, params)
      return
    end
    json_response = @hub_interface.register(payload, params)
    render_response(json_response, options) do
      msg = json_response["msg"] || "Hub registration complete"
      print_green_success msg
    end
  end

  protected

  def print_hub_usage_data_details(json_response, options)
    usage_data = json_response['data']

    #print_h2 "Appliance Info", options

    print_description_list({
      "Appliance URL" => lambda {|it| it['applianceUrl'] },
      "Appliance Version" => lambda {|it| it['applianceVersion'] },
      # "Appliance Unique ID" => lambda {|it| ['hubUniqueId'] },
      "Stats Version" => lambda {|it| it['statsVersion'] },
      "Last Login" => lambda {|it| it['lastLoggedIn'] ? format_local_dt(it['lastLoggedIn']) : '' },
      "Timestamp (ms)" => lambda {|it| it['ts'] },
      "Date" => lambda {|it| parse_time(it['ts']/1000, "yyyy-MM-dd'T'HH:mm:sss'Z'") }
    }, usage_data, options)
   

    # print_h2 "Appliance Usage", options
    # if usage_data['appliance']
    #   # print_h2 "Appliance", options
    #   print_description_list({
    #     "Total Groups" => lambda {|it| it['appliance']['totalGroups'] },
    #     "Total Clouds" => lambda {|it| it['appliance']['totalClouds'] },
    #   }, usage_data, options)
    # end

    print_h2 "Appliance Usage", options
    # print_details_raw(usage_data['appliance'], options)
    print_details(usage_data['appliance'], {
      pretty: true,
      column_format: {
        totalMemory: lambda {|it| format_bytes it['totalMemory'] },
        totalMemoryUsed: lambda {|it| format_bytes it['totalMemoryUsed'] },
        totalStorage: lambda {|it| format_bytes it['totalStorage'] },
        totalStorageUsed: lambda {|it| format_bytes it['totalStorageUsed'] },
        managedMemoryTotal: lambda {|it| format_bytes it['managedMemoryTotal'] },
        managedMemoryUsed: lambda {|it| format_bytes it['managedMemoryUsed'] },
        managedStorageTotal: lambda {|it| format_bytes it['managedStorageTotal'] },
        managedStorageUsed: lambda {|it| format_bytes it['managedStorageUsed'] },
        unmanagedMemoryTotal: lambda {|it| format_bytes it['unmanagedMemoryTotal'] },
        unmanagedMemoryUsed: lambda {|it| format_bytes it['unmanagedMemoryUsed'] },
        unmanagedStorageTotal: lambda {|it| format_bytes it['unmanagedStorageTotal'] },
        unmanagedStorageUsed: lambda {|it| format_bytes it['unmanagedStorageUsed'] },
        cloudTypes: lambda {|it| it['cloudTypes'] ? it['cloudTypes'].collect {|row| "#{row['code']} (#{row['count']})"}.join(", ") : '' },
        instanceTypes: lambda {|it| it['instanceTypes'] ? it['instanceTypes'].collect {|row| "#{row['code']} (#{row['count']})"}.join(", ") : '' },
        provisionTypes: lambda {|it| it['provisionTypes'] ? it['provisionTypes'].collect {|row| "#{row['code']} (#{row['count']})"}.join(", ") : '' },
        serverTypes: lambda {|it| it['serverTypes'] ? it['serverTypes'].collect {|row| "#{row['code']} (#{row['count']})"}.join(", ") : '' },
        clusterTypes: lambda {|it| it['clusterTypes'] ? it['clusterTypes'].collect {|row| "#{row['code']} (#{row['count']})"}.join(", ") : '' },
      }
    })
    
    # print_h2 "Clouds", options
    # print_h2 "Hosts", options
    # print_h2 "Instances", options

     
  end


  

end
