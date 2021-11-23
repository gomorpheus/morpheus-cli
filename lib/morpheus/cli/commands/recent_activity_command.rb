require 'morpheus/cli/cli_command'

class Morpheus::Cli::RecentActivityCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'recent-activity'

  # deprecated 4.2.10
  set_command_hidden

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @dashboard_interface = @api_client.dashboard
    @accounts_interface = @api_client.accounts
  end

  # def usage
  #   "Usage: morpheus #{command_name}"
  # end

  def handle(args)
    print_error yellow,"[DEPRECATED] The command `recent-activity` is deprecated. It has been replaced by `activity list`.",reset,"\n"
    list(args)
  end

  def list(args)
    params, options = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on( '-u', '--user USER', "Username or ID" ) do |val|
        options[:user] = val
      end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val).utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val).utc.iso8601
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
List recent activity.
This command is deprecated. Use `activity` instead.
EOT
    end
    # parse options
    optparse.parse!(args)
    # parse arguments
    verify_args!(args:args, count:0, optparse:optparse)
    # establish connection to @remote_appliance
    connect(options)
    # construct request
    #params.merge!(parse_query_options(options)) # inject -Q PARAMS
    params.merge!(parse_list_options(options)) # inject phrase,sort,max,offset and -Q PARAMS
    # parse my options
    # this api allows filter by params.accountId
    # todo: use OptionSourceHelper parse_tenant_id() instead of AccountsHelper
    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    if account_id
      params['accountId'] = account_id
    end
    if options[:start]
      params['start'] = options[:start]
    end
    if options[:end]
      params['end'] = options[:end]
    end

    # parse --user
    if options[:user]
      user_ids = parse_user_id_list(options[:user])
      return 1 if user_ids.nil?
      # userId limited to one right now
      # params['userId'] = user_ids
      params['userId'] = user_ids[0]
    end
    
    # setup interface and check for dry run?
    @dashboard_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @dashboard_interface.dry.recent_activity(params)
      return 0, nil
    end
    
    # make the request
    json_response = @dashboard_interface.recent_activity(params)
    
    # determine exit status
    exit_code, err = 0, nil
    
    # could error if there are no results.
    # if json_response['activity'].empty?
    #   exit_code = 3 
    #   err = "0 results found"
    # end
    
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
      print_h1 title, subtitles
      print cyan
      items = json_response["activity"]
      if items.empty?
        puts "No activity found."
        print reset,"\n"
      else
        # JD: this api response is funky, no meta and it includes date objects
        # ok then its gone, get good api response data gosh darnit!
        # use /api/activity instead
        items = items.select { |item| item['_id'] || item['name'] }
        columns = [
          # {"ID" => lambda {|item| item['id'] } },
          # {"SEVERITY" => lambda {|item| format_activity_severity(item['severity']) } },
          {"TYPE" => lambda {|item| item['activityType'] } },
          {"AUTHOR" => lambda {|item| item['userName'] || '' } },
          {"MESSAGE" => lambda {|item| item['message'] || '' } },
          {"OBJECT" => lambda {|item| format_activity_display_object(item) } },
          {"WHEN" => lambda {|item| format_local_dt(item['ts']) } }
        ]
        print as_pretty_table(items, columns, options)
        print reset,"\n"
      end
      return exit_code, err
    end
  end

  protected

  def format_activity_severity(severity, return_color=cyan)
    out = ""
    status_string = severity
    if status_string == 'critical'
      out << "#{red}#{status_string.capitalize}#{return_color}"
    elsif status_string == 'warning'
      out << "#{yellow}#{status_string.capitalize}#{return_color}"
    elsif status_string == 'info'
      out << "#{cyan}#{status_string.capitalize}#{return_color}"
    else
      out << "#{cyan}#{status_string}#{return_color}"
    end
    out
  end

  def format_activity_display_object(item)
    out = ""
    if item['name']
      out << item['name']
    end
    if item['objectType']
      out << " (#{item['objectType']} #{item['objectId']})"
    end
    if item['deleted']
      out << " [deleted]"
    end
    out
  end

end
