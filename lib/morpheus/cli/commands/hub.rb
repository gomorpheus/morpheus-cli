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
        "Registered" => lambda {|it| format_boolean(it['hub']['registered']) },
        "Appliance ID" => lambda {|it| it['hub']['applianceUniqueId'] },
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
      # print_description_list({
      #   "Total Clouds" => lambda {|it| it['appliance']['totalClouds'] },
      #   "Total Groups" => lambda {|it| it['appliance']['totalGroups'] },
      #   # etc
      # }, usage_data, options)
      puts as_json(json_response['data'], {:pretty_json => false})
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
Checkin with the hub, sending the current appliance usage data.
The checkin is skipped if the appliance is not yet registered or
if if the appliance is not configured to send data to the hub (reportStatus: false).
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

  # custom rendering to print Message below description list
  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      # show log message settings...
      print_h2 "Message", options
      print cyan
      puts record['message']
      print reset,"\n"
    end
  end

  def audit_log_object_key
    "auditLog"
  end

  def audit_log_list_key
    "auditLogs"
  end

  def audit_log_list_column_definitions(options={})
    {
      "ID" => 'id',
      "Level" => lambda {|it| format_log_level(it['level']) },
      "Message" => {display_method:'message', max_width: (options[:wrap] ? nil : 75)}, 
      "Event Type" => 'eventType',
      "Object" => lambda {|it| "#{it['objectClass']} #{it['objectId']}".strip },
      # "Object Type" => 'objectClass',
      # "Object ID" => 'objectId',
      "User" => lambda {|it| 
        if it['actualUser'] && it['user'] && it['actualUser']['username'] != it['user']['username']
          it['user']['username'] + '(' + it['actualUser']['username'].to_s + ')'
        elsif it['user']
          it['user']['username']
        else
          # system or deleted user maybe?
        end
      },
      # "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
    }
  end

  def audit_log_column_definitions(options={})
    {
      "ID" => 'id',
      "Level" => lambda {|it| format_log_level(it['level']) },
      #"Message" => 'message', 
      "Event Type" => 'eventType',
      "Object Type" => 'objectClass',
      "Object ID" => 'objectId',
      "User" => lambda {|it| 
        if it['actualUser'] && it['user'] && it['actualUser']['username'] != it['user']['username']
          it['user']['username'] + '(' + it['actualUser']['username'].to_s + ')'
        elsif it['user']
          it['user']['username']
        else
          # system or deleted user maybe?
        end
      },
      # "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
    }
  end

  def find_audit_log_by_name_or_id(val)
    return find_audit_log_by_id(val)
  end

  def find_audit_log_by_id(id)
    begin
      json_response = @audit_interface.get(id)
      return json_response[audit_log_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Audit Log not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_audit_log_by_name(name)
    raise_command_error "finding audit log by name not supported"
  end

end
