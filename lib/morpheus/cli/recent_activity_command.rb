require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::RecentActivityCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'recent-activity'

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @dashboard_interface = @api_client.dashboard
    @accounts_interface = @api_client.accounts
  end

  def usage
    "Usage: morpheus #{command_name}"
  end

  def handle(args)
    list(args)
  end
  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val).iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val).iso8601
      end
      build_common_options(opts, options, [:account, :list, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      params = {}
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @dashboard_interface.dry.recent_activity(account_id, params)
        return
      end
      json_response = @dashboard_interface.recent_activity(account_id, params)

      if options[:json]
        puts as_json(json_response, options, "activity")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "activity")
        return 0
      elsif options[:csv]
        # strip date lines
        json_response['activity'] = json_response['activity'].reject {|it| it.keys.size == 1 && it.keys[0] == 'date' }
        puts records_as_csv(json_response['activity'], options)
        return 0
      end
      title = "Recent Activity"
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
        return 0
      end
      # JD: this api response is funky, no meta and it includes date objects
      items = items.select { |item| item['_id'] || item['name'] }
      print_recent_activity_table(items, options)
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def print_recent_activity_table(items, opts={})
    columns = [
      # {"ID" => lambda {|item| item['id'] } },
      # {"SEVERITY" => lambda {|item| format_activity_severity(item['severity']) } },
      {"TYPE" => lambda {|item| item['activityType'] } },
      {"AUTHOR" => lambda {|item| item['userName'] || '' } },
      {"MESSAGE" => lambda {|item| item['message'] || '' } },
      # {"NAME" => lambda {|item| item['name'] } },
      {"OBJECT" => lambda {|item| format_activity_display_object(item) } },
      {"WHEN" => lambda {|item| format_local_dt(item['ts']) } }
      # {"WHEN" => lambda {|item| "#{format_duration(item['ts'])} ago" } }
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(items, columns, opts)
  end

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
