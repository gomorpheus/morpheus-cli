require 'morpheus/cli/cli_command'

class Morpheus::Cli::Snapshots
  include Morpheus::Cli::CliCommand

  set_command_name :snapshots
  set_command_description "View or remove snapshot"
  register_subcommands :get, :remove

  alias_subcommand :details, :get
  set_default_subcommand :get

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @snapshots_interface = @api_client.snapshots
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.footer = "Get Snapshot details." + "\n" +
                    "[id] is required. This is the id of the snapshot."
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end

    connect(options)
    id_list = parse_id_list(args)

    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(arg, options)
    begin

      @snapshots_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @snapshots_interface.dry.get(arg.to_i)
        return
      end

      json_response = @snapshots_interface.get(arg.to_i)
      if options[:json]
        puts as_json(json_response, options, "snapshot")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "snapshot")
        return 0
      end

      if options[:csv]
        puts records_as_csv([json_response['snapshot']], options)
        return 0
      end
      snapshot = json_response['snapshot']

      print_h1 "Snapshot Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "External Id" => 'externalId',
        "Status" => 'status',
        "State" => 'state',
        "Snapshot Type" => 'snapshotType',
        "Snapshot Created" => 'snapshotCreated',
        "Cloud" => 'zone.name',
        "Datastore" => 'datastore',
        "Parent Snapshot" => 'parentSnapshot',
        "Active" => 'currentlyActive',
        "Date Created" => 'dateCreated'
      }
      print_description_list(description_cols, snapshot)

      print reset, "\n"

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    snapshot_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
     opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove/Delete a snapshot." + "\n" +
                    "[id] is required. This is the id of the snapshot to delete."
    end
    
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    snapshot_id = args[0].to_i
    connect(options)
    begin
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove a snapshot?", options)
        exit 1
      end
 
      payload = {}
      if options[:dry_run]
        print_dry_run @snapshots_interface.dry.remove(snapshot_id, payload)
        return
      end
      
      json_response = @snapshots_interface.remove(snapshot_id, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshot delete initiated."
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
end