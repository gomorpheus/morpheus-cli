require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::RecentActivityCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'recent-activity'
  set_command_hidden # remove once this is done

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
    build_common_options(opts, options, [:account, :list, :json, :dry_run])
  end
  optparse.parse!(args)
  connect(options)
  begin
    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    params = {}
    [:phrase, :offset, :max, :sort, :direction, :start, :end].each do |k|
    params[k] = options[k] unless options[k].nil?
  end
  if options[:dry_run]
    print_dry_run @dashboard_interface.dry.recent_activity(account_id, params)
    return
  end
  json_response = @dashboard_interface.recent_activity(account_id, params)
    if options[:json]
    print JSON.pretty_generate(json_response)
    print "\n"
  else
    
    # todo: impersonate command and show that info here

    print "\n" ,cyan, bold, "Dashboard\n","==================", reset, "\n\n"
    print cyan
        print "\n"
    puts "Coming soon.... see --json"
    print "\n"

    print reset,"\n"

  end
rescue RestClient::Exception => e
  print_rest_exception(e, options)
  exit 1
end
end

end
