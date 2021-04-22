require 'morpheus/cli/cli_command'

# CLI command VDI Allocation management
# UI is Tools: VDI Allocations
# API is /vdi-allocations and returns vdiAllocations
class Morpheus::Cli::VdiAllocationsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::VdiHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'vdi-allocations'
  set_command_description "View VDI allocations"

  register_subcommands :list, :get
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @vdi_pools_interface = @api_client.vdi_pools
    @vdi_allocations_interface = @api_client.vdi_allocations
    @option_types_interface = @api_client.option_types
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
      build_standard_list_options(opts, options)
      opts.footer = "List VDI allocations."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @vdi_allocations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_allocations_interface.dry.list(params)
      return
    end
    json_response = @vdi_allocations_interface.list(params)
    render_response(json_response, options, vdi_allocation_list_key) do
      vdi_allocations = json_response[vdi_allocation_list_key]
      print_h1 "Morpheus VDI Allocations", parse_list_subtitles(options), options
      if vdi_allocations.empty?
        print cyan,"No VDI allocations found.",reset,"\n"
      else
        list_columns = vdi_allocation_column_definitions.upcase_keys!
        print as_pretty_table(vdi_allocations, list_columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[allocation]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific VDI allocation.
[allocation] is required. This is the id of a VDI allocation.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @vdi_allocations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_allocations_interface.dry.get(id, params)
      return
    end
    json_response = @vdi_allocations_interface.get(id, params)
    vdi_allocation = json_response[vdi_allocation_object_key]
    render_response(json_response, options, vdi_allocation_object_key) do
      print_h1 "VDI Allocation Details", [], options
      print cyan
      show_columns = vdi_allocation_column_definitions
      print_description_list(show_columns, vdi_allocation)
      print reset,"\n"
    end
    return 0, nil
  end

  private

  def vdi_allocation_column_definitions()
    {
      "ID" => lambda {|it| it['id'] },
      "Pool" => lambda {|it| it['pool'] ? it['pool']['name'] : nil },
      "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : nil },
      "User" => lambda {|it| it['user'] ? it['user']['username'] : nil },
      "Status" => lambda {|it| format_vdi_allocation_status(it) },
      "Created" => lambda {|it| format_local_dt it['dateCreated'] },
      "Release Date" => lambda {|it| format_local_dt it['releaseDate'] }
    }
  end

  def vdi_allocation_list_column_definitions()
    vdi_allocation_column_definitions()
  end

  # finders are in VdiHelper mixin

end
