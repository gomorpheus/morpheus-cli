require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupResultsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::BackupsHelper
  # include Morpheus::Cli::ProvisioningHelper
  # include Morpheus::Cli::OptionSourceHelper

  set_command_hidden # hide and prefer backups list-results, get-result, etc. for now

  set_command_name :'backup-results'

  register_subcommands :list, :get, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backups_interface = @api_client.backups
    @backup_results_interface = @api_client.backup_results
  end

  def handle(args)
    handle_subcommand(args)
  end  

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups list-results [search]"
      opts.on('--backup BACKUP', String, "Backup Name or ID") do |val|
        options[:backup] = val
      end
      opts.on('--instance INSTANCE', String, "Instance Name or ID") do |val|
        options[:instance] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List backup results."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, max:1)
    parse_list_options!(args, options, params)
    execute_api(@backup_results_interface, :list, [], options, 'results') do |json_response|
      backup_results = json_response['results']
      subtitles = []
      subtitles << "Backup: #{options[:backup]}" if options[:backup]
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Backup Results", subtitles, options
      if backup_results.empty?
        print yellow,"No backup results found.",reset,"\n"
      else
        print as_pretty_table(backup_results, backup_result_list_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups get-result [result]"
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific backup result.
[result] is required. This is the id of a backup result.
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
        backup_result = find_backup_result_by_name(id)
        if backup_result
          backup_result['id']
        else
          return 1, "backup result not found for name '#{id}'"
        end
      end
    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @backup_results_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_results_interface.dry.get(id, params)
      return
    end
    json_response = @backup_results_interface.get(id, params)
    backup_result = json_response['result']
    render_response(json_response, options, 'result') do
      backup_result = json_response['result']
      backups = backup_result['backups'] || []
      print_h1 "Backup Result Details", [], options
      print cyan
      print_description_list(backup_result_column_definitions, backup_result)
      if backup_result['errorMessage']
        print_h2 "Error Message", options
        print red, backup_result['errorMessage'], reset, "\n"
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups remove-result [result]"
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a backup result.
[result] is required. This is the id of a backup result.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup_result = @backup_results_interface.get(args[0])['result']
    # backup_result = find_backup_result_by_name_or_id(args[0])
    # return 1 if backup_result.nil?
    parse_options(options, params)
    confirm!("Are you sure you want to delete the backup result #{backup_result['id']}?", options)
    execute_api(@backup_results_interface, :destroy, [backup_result['id']], options) do |json_response|
      print_green_success "Removed backup result #{backup_result['name']}"
    end
  end

  private

  # helper methods are defined in BackupsHelper

  def parse_list_options!(args, options, params)
    parse_parameter_as_resource_id!(:backup, options, params, 'backupId')
    parse_parameter_as_resource_id!(:instance, options, params, 'instanceId')
    super
  end

end
