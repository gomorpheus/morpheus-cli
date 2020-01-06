require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/logs_helper'
require 'json'

class Morpheus::Cli::LogsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LogsHelper
  register_subcommands :list
  set_command_name :'logs'

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @logs_interface = @api_client.logs
    @servers_interface = @api_client.servers
    @containers_interface = @api_client.containers
    @clusters_interface = @api_client.clusters
  end

  def usage
    "Usage: morpheus #{command_name}"
  end

  def handle(args)
    # list(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('--hosts HOSTS', String, "Filter logs to specific Host ID(s)") do |val|
        params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--servers HOSTS', String, "alias for --hosts") do |val|
        params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--vms HOSTS', String, "alias for --hosts") do |val|
        params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--container CONTAINER', String, "Filter logs to specific Container ID(s)") do |val|
        params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      # opts.on('--nodes HOST', String, "alias for --containers") do |val|
      #   params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      opts.on('--cluster ID', String, "Filter logs to specific Cluster ID") do |val|
        params['clusters'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val) #.utc.iso8601
      end
      # opts.on('--interval TIME','--interval TIME', "Interval of time to include, in seconds. Default is 30 days ago.") do |val|
      #   options[:interval] = parse_time(val).utc.iso8601
      # end
      opts.on('--level VALUE', String, "Log Level. DEBUG,INFO,WARN,ERROR") do |val|
        params['level'] = params['level'] ? [params['level'], val].flatten : val
      end
      opts.on('--table', '--table', "Format ouput as a table.") do
        options[:table] = true
      end
      opts.on('-a', '--all', "Display all details: entire message." ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List logs for a container.\n" +
                    "[id] is required. This is the id of a container."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      params['query'] = params.delete('phrase') if params['phrase']
      params['order'] = params['direction'] unless params['direction'].nil? # old api version expects order instead of direction
      params['startMs'] = (options[:start].to_i * 1000) if options[:start]
      params['endMs'] = (options[:end].to_i * 1000) if options[:end]
      params['interval'] = options[:interval].to_s if options[:interval]
      # could find_by_name_or_id for params['servers'] and params['containers']
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.list(params)
        return
      end
      json_response = @logs_interface.list(params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result

      title = "Morpheus Logs"
      subtitles = parse_list_subtitles(options)
      if options[:start]
        subtitles << "Start: #{options[:start]}".strip
      end
      if options[:end]
        subtitles << "End: #{options[:end]}".strip
      end
      if params['query']
        subtitles << "Search: #{params['query']}".strip
      end
      if params['servers']
        subtitles << "Servers: #{params['servers']}".strip
      end
      if params['containers']
        subtitles << "Containers: #{params['containers']}".strip
      end
      if params['clusters']
        subtitles << "Clusters: #{params['clusters']}".strip
      end
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      print_h1 title, subtitles, options
      logs = json_response['data'] || json_response['logs']
      if logs.empty?
        print "#{cyan}No logs found.#{reset}\n"
      else
        print format_log_records(logs, options)
        print_results_pagination({'meta'=>{'total'=>(json_response['total']['value'] rescue json_response['total']),'size'=>logs.size,'max'=>(json_response['max'] || options[:max]),'offset'=>(json_response['offset'] || options[:offset] || 0)}})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

end
