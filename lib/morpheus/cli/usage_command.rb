require 'morpheus/cli/cli_command'

# CLI command usages
# UI is Costing - Usage
# API is /billing and returns usages
class Morpheus::Cli::UsageCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'usage'

  register_subcommands :list #, :list_tenant, :list_clouds, :list_zones, :list_zones, :list_zones, :list_zones
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @billing_interface = @api_client.billing
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on( '-t', '--type TYPE', "Filter by type" ) do |val|
        params['type'] = parse_usage_type(val)
      end
      opts.on( '-c', '--cloud CLOUD', "Filter by cloud" ) do |val|
        options[:cloud] = val
      end
      opts.on('--start DATE', String, "Start date in the format YYYY-MM-DD.") do |val|
        params['startDate'] = val #parse_time(val).utc.iso8601
      end
      opts.on('--end DATE', String, "End date in the format YYYY-MM-DD. Default is now.") do |val|
        params['endDate'] = val #parse_time(val).utc.iso8601
      end
      opts.on('--sigdig DIGITS', "Significant digits when rounding cost values for display as currency. Default is 5.") do |val|
        options[:sigdig] = val.to_i
      end
      build_standard_list_options(opts, options)
      opts.footer = "List usages."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    # --cloud
    if options[:cloud]
      params['cloud'] = parse_id_list(options[:cloud]).collect {|cloud_id|
        if cloud_id.to_s =~ /\A\d{1,}\Z/
          cloud_id
        else
          cloud = find_cloud_option(cloud_id)
          return 1 if cloud.nil?
          cloud['id']
        end
      }
    end

    @billing_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @billing_interface.dry.list(params)
      return
    end
    json_response = @billing_interface.list(params)
    usages = json_response[usage_list_key]
    render_response(json_response, options, usage_list_key) do
      print_h1 "Morpheus Usages", parse_list_subtitles(options), options
      if usages.empty?
        print cyan,"No usages found.",reset,"\n"
      else
        list_columns = {
          "ID" => 'id',
          "Cloud" => 'zoneName',
          "Type" => lambda {|it| format_usage_type(it) },
          "Name" => 'name',
          "Plan" => 'planName',
          "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
          "End Date" => lambda {|it| format_local_dt(it['endDate']) },
          "Usage Status" => lambda {|it| format_usage_status(it) },
          "Usage Price" => lambda {|it| format_money(it['price'], it['currency'] || 'USD', {sigdig: (options[:sigdig] || 5)}) },
        }
        print as_pretty_table(usages, list_columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if usages.empty?
      return 1, "no usages found"
    else
      return 0, nil
    end
  end

  
  private

  def usage_object_key
    'usage'
  end

  def usage_list_key
    'usages'
  end

  def format_usage_type(usage)
    #return usage['costDetails']['refType']
    ref_type = usage['costDetails'] ? usage['costDetails']['refType'].to_s : ''
    if ref_type == 'discoveredServer'
      'Discovered'
    elsif ref_type == 'computeServer'
      'Host'
    elsif ref_type == 'container'
      'Container'
    else
      ref_type.to_s
    end
  end

  def parse_usage_type(val)
    type_string = val.to_s.downcase
    if type_string == 'discoveredServer'
      'discoveredServer'
    elsif type_string == 'host'
      'computeServer'
    elsif type_string == 'container'
      'container'
    else
      val
    end
  end

  def format_usage_status(usage, return_color=cyan)
    #return usage['status'].to_s.capitalize
    status_string = usage['status'].to_s
    if status_string == 'stopped'
      return "#{cyan}#{status_string.upcase}#{return_color}"
    else
      return "#{cyan}#{status_string.upcase}#{return_color}"
    end
  end

end
