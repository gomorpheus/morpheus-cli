require 'morpheus/cli/cli_command'

class Morpheus::Cli::Options
  include Morpheus::Cli::CliCommand

  set_command_description "List options by source name or option type"
  set_command_name :'options'
  
  # options is not published yet
  set_command_hidden

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @options_interface = @api_client.options
  end
  
  def handle(args)
    # todo: probably just make these proper subcommands
    # handle_subcommand(args)
    # handle some special cases that do not conform to name, value
    # This also provides some help on their by documenting the required parameters.
    source_name = args[0]
    if source_name == "networkServices"
      network_services(args[1..-1])
    elsif source_name == "zoneNetworkOptions"
      zone_network_options(args[1..-1])
    else
      list(args)
    end
  end

  # This is the default handler for the options command.
  # It shows the NAME and VALUE for the list of "data" returned.
  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: morpheus #{command_name} [source] [option-type]"
      # build_standard_list_options(opts, options)
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View options by source name or list options for a specific library option type.
[source] is required. This is the name of the options source to load eg. "currencies"
[option-type] is required when [source] is 'list'. This is the name or id of an option type to view.

Examples: 
    options currencies
    options dnsRecordType
    options list "widgets"
EOT
    end
    optparse.parse!(args)
    source_name = args[0]
    option_type_id = args.size > 1 ? args[1..-1].join(" ") : nil
    if source_name == "list"
      verify_args!(args:args, optparse:optparse, min: 2)
    else
      verify_args!(args:args, optparse:optparse, count: 1)
    end
    connect(options)
    params.merge!(parse_list_options(options))
    if source_name == "list"
      if option_type_id.to_s =~ /\A\d{1,}\Z/
        params["optionTypeId"] = option_type_id
      else
        option_type = find_by_name_or_id(:option_type, option_type_id)
        if option_type.nil?
          return 1, "Option Type not found by name '#{option_type_id}'"
        end
        params["optionTypeId"] = option_type["id"]
      end
    end
    # could find_by_name_or_id for params['servers'] and params['containers']
    @options_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @options_interface.dry.options_for_source(source_name, params)
      return
    end
    json_response = nil
    begin
      json_response = @options_interface.options_for_source(source_name, params)
    rescue RestClient::Exception => e
      if Morpheus::Logging.debug? # or options[:debug]
        raise e
      end
      if e.response && e.response.code == 404
        raise_command_error("Options source not found by name '#{source_name}'", args, optparse)
      elsif e.response && e.response.code == 500
        # API is actually returning 500, so just expect it
        if e.response.body.to_s.include?("groovy.lang.MissingMethodException")
          raise_command_error("Options source not found by name '#{source_name}'", args, optparse)
        else
          raise e
        end
      else
        raise e
      end
    end
    render_response(json_response, options, "data") do
      records = json_response["data"]
      # print_h1 "Morpheus Options: #{source}", parse_list_subtitles(options), options
      print_h1 "Morpheus Options", ["Source: #{source_name}"] + parse_list_subtitles(options), options
      if records.nil? || records.empty?
        print cyan,"No options found.",reset,"\n"
      else
        print as_pretty_table(records, [:name, :value], options)
        print_results_pagination({size: records.size, total: records.size})
      end
      print reset,"\n"
    end
    return 0, nil
  end

  # handle some well option sources by name

  def network_services(args)
    options = {}
    params = {}
    source_name = "networkServices"
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: morpheus #{command_name} #{source_name} #{args[0]}"
      # build_standard_list_options(opts, options)
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View list of options for source '#{source_name}'.
This is the list of network service types (network server types) that can be added.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 0)
    connect(options)
    params.merge!(parse_list_options(options))
    @options_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @options_interface.dry.options_for_source(source_name, params)
      return
    end
    json_response = @options_interface.options_for_source(source_name, params)
    render_response(json_response, options, "data") do
      records = json_response["data"].collect {|r| r['services']}.compact.flatten
      print_h1 "Morpheus Options", ["Source: #{source_name}"] + parse_list_subtitles(options), options, ""
      if records.nil? || records.empty?
        print cyan,"No options found.",reset,"\n"
      else
        json_response["data"].each do |data_row|
          if data_row['services'] && !data_row['services'].empty?
            services = []
            data_row['services'].each do |service_row|
              services << {name: service_row['name'], code: service_row['code'] , id: service_row['id'], value: service_row['id']}
            end
            # print_h2 "#{data_row['name']} Options", [], options
            print_h2 "#{data_row['name']}", [], options
            print as_pretty_table(services, [:id, :name, :code], options)
          end
        end
      end
      print_results_pagination({size: records.size, total: records.size})
      print reset,"\n"
    end
    return 0, nil
  end
  
#  # this is a really slow one right now, need to look into that.
#   def networks(args)
#   end

  def zone_network_options(args)
    options = {}
    params = {}
    source_name = "zoneNetworkOptions"
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: morpheus #{command_name} #{source_name} #{args[0]}"
      # build_standard_list_options(opts, options)
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View list of options for source '#{source_name}'.
This is the list of networks available when provisioning to a particular cloud and layout.

Required Parameters:
    Cloud ID (zoneId)
    Layout ID (layoutId)

Examples: 
    options #{source_name} -Q zoneId=40&layoutId=1954
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 0)
    connect(options)
    params.merge!(parse_list_options(options))
    @options_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @options_interface.dry.options_for_source(source_name, params)
      return
    end
    # This requires Cloud and Layout -Q zoneId=40&layoutId=1954
    # todo: prompt
    json_response = @options_interface.options_for_source(source_name, params)
    render_response(json_response, options, "data") do
      # This is different, data is a Hash, not an Array...
      networks = json_response["data"]["networks"]
      network_groups = json_response["data"]["networkGroups"]
      network_subnets = json_response["data"]["networkSubnets"]
      records = [networks, network_groups, network_subnets].compact.flatten
      print_h1 "Morpheus Options", ["Source: #{source_name}"] + parse_list_subtitles(options), options, ""
      if records.nil? || records.empty?
        print cyan,"No options found.",reset,"\n"
      else
        if networks && !networks.empty?
          print_h2 "Networks", [], options
          rows = networks.collect {|row| {name: row['name'], value: row['id']} }
          print as_pretty_table(rows, [:name, :value], options)
        end
        if network_groups && !network_groups.empty?
          print_h2 "Network Groups", [], options
          rows = network_groups.collect {|row| {name: row['name'], value: row['id']} }
          print as_pretty_table(rows, [:name, :value], options)
        end
        if network_subnets && !network_subnets.empty?
          print_h2 "Subnets", [], options
          rows = network_subnets.collect {|row| {name: row['name'], value: row['id']} }
          print as_pretty_table(rows, [:name, :value], options)
        end
      end
      print_results_pagination({size: records.size, total: records.size})
      print reset,"\n"
    end
    return 0, nil
  end

end
