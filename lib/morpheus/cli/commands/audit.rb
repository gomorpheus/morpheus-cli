require 'morpheus/cli/cli_command'

class Morpheus::Cli::Audit
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LogsHelper
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::OptionSourceHelper

  set_command_description "View audit log records."
  set_command_name :'audit'
  register_subcommands :list, :get
  
  # audit is not published yet
  set_command_hidden

  # RestCommand settings

  # interfaces
  register_interfaces :audit
  set_rest_interface_name :audit

  # resource name is "Audit Log"
  set_rest_name :audit_log

  # display argument as [id] instead of [audit log]
  set_rest_has_name false
  set_rest_arg "id"

  # def connect(opts)
  #   @api_client = establish_remote_appliance_connection(opts)
  #   @audit_interface = @api_client.audit # @api_client.rest("audit")
  # end
  
  # def handle(args)
  #   handle_subcommand(args)
  # end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on('--user USER', String, "Filter by User Username or ID") do |val|
        params['user'] = params['user'] ? [params['user'], val].flatten : [val]
      end
      opts.on('--level VALUE', String, "Log Level. DEBUG|INFO|WARN|ERROR") do |val|
        params['level'] = params['level'] ? [params['level'], val].flatten : [val]
      end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start date timestamp in standard iso8601 format.") do |val|
        params['startDate'] = val # parse_time(val).utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End date timestamp in standard iso8601 format.") do |val|
        params['endDate'] = val # parse_time(val).utc.iso8601
      end
      build_standard_list_options(opts, options)
      opts.footer = "List audit logs records."
    end
    optparse.parse!(args)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    params.merge!(parse_list_options(options))
    # parse --user id,name
    if params['user']
      user_ids = parse_user_id_list(params['user'])
      return 1 if user_ids.nil?
      params['user'] = user_ids
    end
    # api works with level=INFO|WARN
    if params['level']
      params['level'] = [params['level']].flatten.collect {|it| it.to_s.upcase }.join('|')
    end
    # could find_by_name_or_id for params['servers'] and params['containers']
    @audit_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @audit_interface.dry.list(params)
      return
    end
    json_response = @audit_interface.list(params)

    render_response(json_response, options, rest_list_key) do
      records = json_response[rest_list_key]
      print_h1 "Morpheus Audit Log", parse_list_subtitles(options), options
      if records.nil? || records.empty?
        print cyan,"No #{rest_label_plural.downcase} found.",reset,"\n"
      else
        print as_pretty_table(records, rest_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response) if json_response['meta']
      end
      print reset,"\n"
    end
    return 0, nil
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
