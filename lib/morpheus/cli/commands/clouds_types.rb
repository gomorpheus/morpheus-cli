require 'morpheus/cli/cli_command'

class Morpheus::Cli::CloudTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :get

  # hidden in favor of get-type and list-types
  set_command_hidden

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clouds_interface = @api_client.clouds
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options={}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List cloud types.
EOT
    end
    optparse.parse!(args)
    connect(options)

    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.cloud_types({})
      return 0
    end
    json_response = @clouds_interface.cloud_types(params)
      
    render_response(json_response, options, 'zoneTypes') do
      cloud_types = json_response['zoneTypes']
      subtitles = []        
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Cloud Types", subtitles, options
      if cloud_types.empty?
        print cyan,"No cloud types found.",reset,"\n"
      else
        print cyan
        cloud_types = cloud_types.select {|it| it['enabled'] }
        rows = cloud_types.collect do |cloud_type|
          {id: cloud_type['id'], name: cloud_type['name'], code: cloud_type['code']}
        end
        #print "\n"
        columns = [:id, :name, :code]
        columns = options[:include_fields] if options[:include_fields]
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
        print reset,"\n"
      end
    end
  end

  def get(args)
    options={}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_standard_get_options(opts, options)
            opts.footer = <<-EOT
Get details about a cloud type.
[type] is required. This is the name or id of cloud type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    # construct request
    params.merge!(parse_query_options(options))
    id = args[0]
    cloud_type = nil
    if id.to_s !~ /\A\d{1,}\Z/
      cloud_type = cloud_type_for_name_or_id(id)
      if cloud_type.nil?
        raise_command_error "cloud type not found for name or code '#{id}'"
      end
      id = cloud_type['id']
    end
    # execute request
    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.cloud_type(id.to_i)
      return 0
    end
    json_response = @clouds_interface.cloud_type(id.to_i)
    # render response
    render_response(json_response, options, 'zoneType') do
      cloud_type = json_response['zoneType']
      print_h1 "Cloud Type", [], options
      print cyan
      #columns = rest_type_column_definitions(options)
      columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'code',
        "Enabled" => lambda {|it| format_boolean it['enabled'] },
        "Provision" => lambda {|it| format_boolean it['provision'] },
        "Auto Capacity" => lambda {|it| format_boolean it['autoCapacity'] },
        # "Migration Target" => lambda {|it| format_boolean it['migrationTarget'] },
        "Datastores" => lambda {|it| format_boolean it['hasDatastores'] },
        "Networks" => lambda {|it| format_boolean it['hasNetworks'] },
        "Resource Pools" => lambda {|it| format_boolean it['hasResourcePools'] },
        "Security Groups" => lambda {|it| format_boolean it['hasSecurityGroups'] },
        "Containers" => lambda {|it| format_boolean it['hasContainers'] },
        "Bare Metal" => lambda {|it| format_boolean it['hasBareMetal'] },
        "Services" => lambda {|it| format_boolean it['hasServices'] },
        "Functions" => lambda {|it| format_boolean it['hasFunctions'] },
        "Jobs" => lambda {|it| format_boolean it['hasJobs'] },
        "Discovery" => lambda {|it| format_boolean it['hasDiscovery'] },
        "Cloud Init" => lambda {|it| format_boolean it['hasCloudInit'] },
        "Folders" => lambda {|it| format_boolean it['hasFolders'] },
        # "Marketplace" => lambda {|it| format_boolean it['hasMarketplace'] },
        "Public Cloud" => lambda {|it| format_boolean(it['cloud'] == 'public') },
      }
      print_description_list(columns, cloud_type, options)
      # Option Types
      option_types = cloud_type['optionTypes']
      if option_types && option_types.size > 0
        print_h2 "Option Types", options
        print format_option_types_table(option_types, options, "zone")
      end
      print reset,"\n"
    end
  end

end
