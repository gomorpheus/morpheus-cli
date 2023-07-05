require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupRestoresCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::BackupsHelper
  # include Morpheus::Cli::ProvisioningHelper
  # include Morpheus::Cli::OptionSourceHelper

  set_command_hidden # hide until ready

  set_command_name :'backup-restores'

  register_subcommands :list, :get, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backups_interface = @api_client.backups
    @backup_restores_interface = @api_client.backup_restores
  end

  def handle(args)
    handle_subcommand(args)
  end  

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups list-restores [search]"
      build_standard_list_options(opts, options)
      opts.footer = "List backup restores."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @backup_restores_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_restores_interface.dry.list(params)
      return
    end
    json_response = @backup_restores_interface.list(params)
    backup_restores = json_response['restores']
    render_response(json_response, options, 'restores') do
      print_h1 "Morpheus Backup Restores", parse_list_subtitles(options), options
      if backup_restores.empty?
        print yellow,"No backup restores found.",reset,"\n"
      else
        print as_pretty_table(backup_restores, backup_restore_list_column_definitions.upcase_keys!, options)
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
      opts.banner = "Usage: #{prog_name} backups get-restore [restore]"
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific backup restore.
[restore] is required. This is the id of a backup restore.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    id_list = id_list.collect do |id|
      if id.to_s =~ /\A\d{1,}\Z/
        id
      else
        backup_restore = find_backup_restore_by_name(id)
        if backup_restore
          backup_restore['id']
        else
          return 1, "backup restore not found for name '#{id}'"
        end
      end
    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @backup_restores_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_restores_interface.dry.get(id, params)
      return
    end
    json_response = @backup_restores_interface.get(id, params)
    backup_restore = json_response['restore']
    render_response(json_response, options, 'restore') do
      backup_restore = json_response['restore']
      backups = backup_restore['backups'] || []
      print_h1 "Backup Restore Details", [], options
      print cyan
      print_description_list(backup_restore_column_definitions, backup_restore)
      if backup_restore['errorMessage']
        print_h2 "Error Message", options
        print red, backup_restore['errorMessage'], reset, "\n"
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups remove-restore [restore]"
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a backup restore.
[restore] is required. This is the id of a backup restore.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup_restore = @backup_restores_interface.get(args[0])['restore']
    #backup_restore = find_backup_restore_by_name_or_id(args[0])
    #return 1 if backup_restore.nil?
    parse_options(options, params)
    confirm!("Are you sure you want to delete the backup restore #{backup_restore['id']}?", options)
    execute_api(@backup_restores_interface, :destroy, [backup_restore['id']], options) do |json_response|
      print_green_success "Removed backup restore #{backup_restore['name']}"
    end
  end

  private

  # helper methods are defined in BackupsHelper
  
end
