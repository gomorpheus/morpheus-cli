require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupJobsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::BackupsHelper
  # include Morpheus::Cli::ProvisioningHelper
  # include Morpheus::Cli::OptionSourceHelper

  set_command_hidden # hide until ready

  set_command_name :'backup-jobs'

  register_subcommands :list, :get #, :add, :update, :remove, :run

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backups_interface = @api_client.backups
    @backup_jobs_interface = @api_client.backup_jobs
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
        print as_pretty_table(backup_jobs, backup_job_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if backup_jobs.empty?
      return 1, "no backup jobs found"
    else
      return 0, nil
    end
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[job]")
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
      print_h1 "Backup Job Details", [], options
      print cyan
      print_description_list(backup_job_column_definitions, backup_job)
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_backup_job_option_types)
      build_option_type_options(opts, options, add_backup_job_advanced_option_types)
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
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_backup_job_option_types(), options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_backup_job_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
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
      opts.banner = subcommand_usage("[job] [options]")
      build_option_type_options(opts, options, update_backup_job_option_types)
      build_option_type_options(opts, options, update_backup_job_advanced_option_types)
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
      opts.banner = subcommand_usage("[job] [options]")
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
    @backup_jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backup_jobs_interface.dry.destroy(backup_job['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the backup #{backup['name']}?")
      return 9, "aborted command"
    end
    json_response = @backup_jobs_interface.destroy(backup_job['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed backup job #{backup_job['name']}"
    end
    return 0, nil
  end

  private

  def backup_job_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_backup_job_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'retentionCount', 'fieldLabel' => 'Retention Count', 'type' => 'number', 'displayOrder' => 3},
      {'fieldName' => 'scheduleId', 'fieldLabel' => 'Schedule', 'type' => 'select', 'optionSource' => 'executeSchedules', 'displayOrder' => 4}, # should use jobSchedules instead maybe? do we support manual schedules for backups?
    ]
  end

  def add_backup_job_advanced_option_types
    []
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

end
