require 'morpheus/cli/cli_command'

class Morpheus::Cli::ActivityCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::OperationsHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'activity'
  register_subcommands :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @activity_interface = @api_client.activity
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    exit_code, err = 0, nil
    params, options = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-t','--type TYPE', "Activity Type eg. Provisioning, Admin") do |val|
        options[:type] ||= []
        options[:type] << val
      end
      opts.on('--timeframe TIMEFRAME', String, "Timeframe, eg. hour,day,today,yesterday,week,month,quarter. Default is month") do |val|
        options[:timeframe] = val
      end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start date to search for activity, can be used instead of --timeframe. Default is a month ago.") do |val|
        options[:start] = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "Start date to search for activity. Default is the current time.") do |val|
        options[:end] = parse_time(val) #.utc.iso8601
      end
      opts.on('-u', '--user USER', "User Name or ID" ) do |val|
        options[:user] = val
      end
      opts.on( '--tenant TENANT', String, "Tenant Name or ID" ) do |val|
        options[:tenant] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List activity.
The default timeframe a month ago up until now, with the most recent activity seen first.
The option --timeframe or --start and --end can be used to customized the date period
EOT
    end
    # parse options
    optparse.parse!(args)
    # parse arguments
    verify_args!(args:args, count:0, optparse:optparse)
    # establish connection to @remote_appliance
    connect(options)
    # construct request
    # inject -Q PARAMS and standard list options phrase,max,sort,search
    params.merge!(parse_list_options(options))
    # --type
    if options[:type]
      params['type'] = [options[:type]].flatten.collect {|it| it.to_s.strip.split(",") }.flatten.collect {|it| it.to_s.strip }
    end
    # --timeframe
    if options[:timeframe]
      params['timeframe'] = options[:timeframe]
    end
    # --start
    if options[:start]
      params['start'] = options[:start]
    end
    # --end
    if options[:end]
      params['end'] = options[:end]
    end
    # --user
    if options[:user]
      user_ids = parse_user_id_list(options[:user])
      return 1 if user_ids.nil?
      params['userId'] = user_ids
    end
    # --tenant
    if options[:tenant]
      tenant_ids = parse_tenant_id_list(options[:tenant])
      return 1 if tenant_ids.nil?
      params['tenantId'] = tenant_ids
    end
    
    # execute the api request
    @activity_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @activity_interface.dry.list(params)
      return 0, nil
    end
    json_response = @activity_interface.list(params)
    
    # determine exit status

    # error if there are no results
    if json_response['activity'].empty?
      exit_code = 3 
      err = "No activity results found"
    end
    
    # render output
    render_response(json_response, options, "activity") do
      title = "Activity"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if options[:start]
        subtitles << "Start: #{options[:start]}"
      end
      if options[:end]
        subtitles << "End: #{options[:end]}"
      end
      print_h1 title, subtitles, options
      records = json_response["activity"]
      if records.empty?
        print yellow, "No activity found.",reset,"\n"
      else
        columns = [
          # {"SEVERITY" => lambda {|record| format_activity_severity(record['severity']) } },
          {"TYPE" => lambda {|record| record['activityType'] } },
          {"NAME" => lambda {|record| record['name'] } },
          {"RESOURCE" => lambda {|record| "#{record['objectType']} #{record['objectId']}" } },
          {"MESSAGE" => lambda {|record| record['message'] || '' } },
          {"USER" => lambda {|record| record['user'] ? record['user']['username'] : record['userName'] } },
          #{"DATE" => lambda {|record| "#{format_duration_ago(record['ts'] || record['timestamp'])}" } },
          {"DATE" => lambda {|record| 
            # show full time if searching for custom timerange, otherwise the default is to show relative time
            if params['start'] || params['end'] || params['timeframe']
              "#{format_local_dt(record['ts'] || record['timestamp'])}"
            else
              "#{format_duration_ago(record['ts'] || record['timestamp'])}"
            end

          } },
        ]
        print as_pretty_table(records, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return exit_code, err
  end

  protected

end
