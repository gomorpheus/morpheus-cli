require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupJobsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::BackupsHelper
  # include Morpheus::Cli::ProvisioningHelper
  # include Morpheus::Cli::OptionSourceHelper

  set_command_hidden # hide until ready

  set_command_name :'backup-jobs'

  register_subcommands :list, :get, :add, :update, :remove, :execute

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backups_interface = @api_client.backups
    @backup_jobs_interface = @api_client.backup_jobs
    @backup_settings_interface = @api_client.backup_settings
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end  

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups list-jobs [search]"
      build_standard_list_options(opts, options)
      opts.footer = "List backup jobs."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @backup_jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_jobs_interface.dry.list(params)
      return
    end
    json_response = @backup_jobs_interface.list(params)
    backup_jobs = json_response['jobs']
    render_response(json_response, options, 'jobs') do
      print_h1 "Morpheus Backup Jobs", parse_list_subtitles(options), options
      if backup_jobs.empty?
        print yellow,"No backup jobs found.",reset,"\n"
      else
        print as_pretty_table(backup_jobs, backup_job_list_column_definitions.upcase_keys!, options)
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
      # opts.banner = subcommand_usage("[job]")
      opts.banner = "Usage: #{prog_name} backups get-job [job]"
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific backup job.
[job] is required. This is the id or name a backup job.
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
        backup_job = find_backup_job_by_name(id)
        if backup_job
          backup_job['id']
        else
          return 1, "backup job not found for name '#{id}'"
        end
      end
    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @backup_jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_jobs_interface.dry.get(id, params)
      return
    end
    json_response = @backup_jobs_interface.get(id, params)
    backup_job = json_response['job']
    render_response(json_response, options, 'job') do
      backup_job = json_response['job']
      backups = backup_job['backups'] || []
      print_h1 "Backup Job Details", [], options
      print cyan
      columns = backup_job_column_definitions
      columns.delete("Provider") if backup_job['backupProvider'].nil?
      columns.delete("Repository") if backup_job['backupRepository'].nil?
      print_description_list(columns, backup_job)
      # print reset,"\n"
      print_h2 "Backups", options
      if backups.empty?
        print yellow,"This job has no backups associated with it.",reset,"\n"
      else
        print as_pretty_table(backups, [:id, :name], options)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups add-job [name]"
      build_option_type_options(opts, options, add_backup_job_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new backup job
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'job' => parse_passed_options(options)})
    else
      payload.deep_merge!({'job' => parse_passed_options(options)})

      avail_job_types = @options_interface.options_for_source('backupJobTypes',{})['data']
      if avail_job_types.empty?
        raise_command_error "No available backup job types found"
      else
        params["jobTypeId"] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobTypeId', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => avail_job_types, 'defaultValue' => avail_job_types[0] ? avail_job_types[0]['name'] : nil, 'required' => true}], options[:options], @api_client)["jobTypeId"]
      end

      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_backup_job_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      if params['scheduleId'] == 'manual' || params['scheduleId'] == ''
        params['scheduleId'] = nil
      end

      job_type_config = Morpheus::Cli::OptionTypes.prompt(backup_job_type_option_types("new", params["jobTypeId"], options), options[:options].deep_merge({:context_map => {'domain' => ''}}), @api_client, options[:params])
      job_type_config.deep_compact!
      params.deep_merge!(job_type_config)
      payload['job'].deep_merge!(params)
    end
    @backup_jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_jobs_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @backup_jobs_interface.create(payload)
    backup_job = json_response['job']
    render_response(json_response, options, 'job') do
      print_green_success "Added backup job #{backup_job['name']}"
      return _get(backup_job["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups update-job [job]"
      build_option_type_options(opts, options, update_backup_job_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a backup job.
[job] is required. This is the name or id of a backup job.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup_job = find_backup_job_by_name_or_id(args[0])
    return 1 if backup_job.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'job' => parse_passed_options(options)})
    else
      payload.deep_merge!({'job' => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_backup_job_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      if v_prompt['scheduleId'] == 'manual' || v_prompt['scheduleId'] == ''
        v_prompt['scheduleId'] = nil
      end
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_backup_job_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload.deep_merge!({'job' => params})
      if payload['job'].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @backup_jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_jobs_interface.dry.update(backup_job['id'], payload)
      return
    end
    json_response = @backup_jobs_interface.update(backup_job['id'], payload)
    backup_job = json_response['job']
    render_response(json_response, options, 'job') do
      print_green_success "Updated backup job #{backup_job['name']}"
      return _get(backup_job["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups remove-job [job]"
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a backup job.
[job] is required. This is the name or id of a backup job.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup_job = find_backup_job_by_name_or_id(args[0])
    return 1 if backup_job.nil?
    parse_options(options, params)
    confirm!("Are you sure you want to delete the backup job #{backup_job['name']}?", options)
    execute_api(@backup_jobs_interface, :destroy, [backup_job['id']], options) do |json_response|
      print_green_success "Removed backup job #{backup_job['name']}"
    end
  end

  def execute(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} backups execute-job [job]"
      build_standard_post_options(opts, options)
      opts.footer = <<-EOT
Execute a backup job to create a new backup result for all the backups in the job.
[job] is required. This is the name or id of a backup job.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup_job = find_backup_job_by_name_or_id(args[0])
    return 1 if backup_job.nil?
    parse_payload(options) do |payload|
    end
    execute_api(@backup_jobs_interface, :execute_job, [backup_job['id']], options, 'job') do |json_response|
      print_green_success "Executing backup job #{backup_job['name']}"
      # should get the result maybe, or could even support refreshing until it is complete...
      # return _get(backup_job["id"], {}, options)
    end
  end

  private

  def backup_job_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Next" => lambda {|it| format_local_dt(it['nextFire']) },
      "Retention Count" => lambda {|it| it['retentionCount'] rescue '' },
      "Provider" => lambda {|it| it['backupProvider']['name'] rescue '' },
      "Repository" => lambda {|it| it['backupRepository']['name'] rescue '' },
      "Source" => lambda {|it| it['source'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def backup_job_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Next" => lambda {|it| format_local_dt(it['nextFire']) },
      "Retention Count" => lambda {|it| it['retentionCount'] rescue '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_backup_job_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => false, 'displayOrder' => 2}
    ]
  end

  def update_backup_job_option_types
    add_backup_job_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def update_backup_job_advanced_option_types
    add_backup_job_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def backup_job_type_option_types(job_action, backup_job_type, options)
    backup_settings = @backup_settings_interface.get(options)["backupSettings"]
    # get job defaults
    default_retention_count = options.dig('backupJob', 'retentionCount') || backup_settings["retentionCount"]
    default_schedule = options.dig('backupJob', 'scheduleTypeId') || backup_settings.dig("defaultSchedule", "id")
    default_synthetic_enabled = options.dig('backupJob', 'syntheticFullEnabled') || backup_settings["defaultSyntheticFullBackupsEnabled"]
    default_synthetic_schedule = options.dig('backupJob', 'syntheticFullSchedule') || backup_settings.dig("defaultSyntheticFullBackupSchedule", "id")
    job_input_params = {jobAction: job_action, id: backup_job_type}
    job_inputs = @options_interface.options_for_source('backupJobOptionTypes', job_input_params)['data']['optionTypes']
    job_inputs.each do | input |
      # set input defaults from global settings
      input['defaultValue'] = case input['fieldName']
                              when "retentionCount"
                                default_retention_count
                              when "scheduleTypeId"
                                default_schedule
                              when "syntheticFullEnabled"
                                default_synthetic_enabled
                              when "syntheticFullSchedule"
                                default_synthetic_schedule
                              end
    end

    job_inputs
  end

  def get_backup_job_option_types(job_action, backup_type, options)

  end

end
