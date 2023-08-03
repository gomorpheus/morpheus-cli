
require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::BackupsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper
  
  set_command_description "View and manage backups"
  set_command_name :'backups'
  register_subcommands :list, :get, :add, :update, :remove, :execute #, :restore
  register_subcommands :list_jobs, :get_job, :add_job, :update_job, :remove_job, :execute_job
  register_subcommands :list_results, :get_result, :remove_result
  register_subcommands :list_restores, :get_restore, :remove_restore

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backups_interface = @api_client.backups
    @backup_jobs_interface = @api_client.backup_jobs
    @backup_results_interface = @api_client.backup_results
    @backup_restores_interface = @api_client.backup_restores
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
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
      opts.footer = "List backups."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    parse_options(options, params)
    execute_api(@backups_interface, :list, [], options, 'backup') do |json_response|
      backups = json_response['backups']
      print_h1 "Morpheus Backups", parse_list_subtitles(options), options
      if backups.empty?
        print cyan,"No backups found.",reset,"\n"
      else
        print as_pretty_table(backups, backup_list_column_definitions.upcase_keys!, options)
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
      opts.banner = subcommand_usage("[backup]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific backup.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    parse_options(options, params)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    if id.to_s !~ /\A\d{1,}\Z/
      record = find_by_name(:backup, id)
      if record.nil?
        return 1, "Backup not found for '#{id}'"
      end
      id = record['id']
    end
    options[:params] = params # parse_options(options, params)
    options.delete(:payload)
    execute_api(@backups_interface, :get, [id], options, 'backup') do |json_response|
      backup = json_response['backup']
      print_h1 "Backup Details", [], options
      print cyan
      columns = backup_column_definitions
      columns.delete("Instance") if backup['instance'].nil?
      columns.delete("Container ID") if backup['containerId'].nil?
      columns.delete("Host") if backup['server'].nil?
      print_description_list(columns, backup, options)
      print reset,"\n"
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--source VALUE', String, "Backup Source: instance, host or provider") do |val|
        options[:options]['source'] = val
      end
      opts.on('--instance VALUE', String, "Instance Name or ID") do |val|
        options[:options]['source'] = 'instance'
        options[:options]['instanceId'] = val
      end
      opts.on('--host VALUE', String, "Host Name or ID") do |val|
        options[:options]['source'] = 'server'
        options[:options]['serverId'] = val
      end
      opts.on('--server VALUE', String, "alias for --host") do |val|
        options[:options]['source'] = 'server'
        options[:options]['serverId'] = val
      end
      opts.add_hidden_option('--server')
      opts.on('--name VALUE', String, "Name") do |val|
        options[:options]['name'] = val
      end
      # build_option_type_options(opts, options, add_backup_option_types)
      build_standard_add_many_options(opts, options)
      opts.footer = <<-EOT
Create a new backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    parse_payload(options, 'backup') do |payload|
      # v_prompt = Morpheus::Cli::OptionTypes.no_prompt(add_backup_option_types, options[:options], @api_client)
      # v_prompt.deep_compact!.booleanize! # remove empty values and convert checkbox "on" and "off" to true and false
      # params.deep_merge!(v_prompt)
      location_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'source', 'fieldLabel' => 'Source', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Host', 'value' => 'server'}, {'name' => 'Provider', 'value' => 'provider'}], 'defaultValue' => 'instance', 'required' => true, 'description' => 'Where is the backup located?'}], options[:options], @api_client)['source']
      params['locationType'] = location_type
      if location_type == 'instance'
        # Instance
        avail_instances = @instances_interface.list({max:10000})['instances'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        params['instanceId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceId', 'fieldLabel' => 'Instance', 'type' => 'select', 'selectOptions' => avail_instances, 'required' => true}], options[:options], @api_client)['instanceId']
        # Name
        params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Backup Name'}], options[:options], @api_client)['name']
      elsif location_type == 'server'
        # Server
        avail_servers = @servers_interface.list({max:10000, 'vmHypervisor' => nil, 'containerHypervisor' => nil})['servers'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        params['serverId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'serverId', 'fieldLabel' => 'Host', 'type' => 'select', 'selectOptions' => avail_servers, 'required' => true}], options[:options], @api_client)['serverId']
        # Name
        params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Backup Name'}], options[:options], @api_client)['name']
      elsif location_type == 'provider'
        # todo: prompt for provider inputs
        # sourceProviderId
        # storageProvider
      end
      # POST to /create to get available option info for containers, backupTypes, backupProviderTypes, etc.
      payload['backup'].deep_merge!(params)
      create_results = @backups_interface.create_options(payload)

      if location_type == 'instance' || location_type == 'server'
        if location_type == 'instance'
          # Container
          avail_containers = (create_results['containers'] || []).collect {|it| {'name' => it['name'], 'value' => it['id']} }
          if avail_containers.empty?
            raise_command_error "No available containers found for selected instance"
          else
            params['containerId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'containerId', 'fieldLabel' => 'Container', 'type' => 'select', 'selectOptions' => avail_containers, 'defaultValue' => avail_containers[0] ? avail_containers[0]['name'] : nil, 'required' => true}], options[:options], @api_client)['containerId']
          end
        elsif location_type == 'server'
          
        end
        # Backup Type
        avail_backup_types = (create_results['backupTypes'] || []).collect {|it| {'name' => it['name'], 'value' => it['code']} }
        if avail_backup_types.empty?
          raise_command_error "No available backup types found"
        else
          params['backupType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'backupType', 'fieldLabel' => 'Backup Type', 'type' => 'select', 'selectOptions' => avail_backup_types, 'defaultValue' => avail_backup_types[0] ? avail_backup_types[0]['name'] : nil, 'required' => true}], options[:options], @api_client)['backupType']  
        end

        # Job / Schedule
        params['jobAction'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobAction', 'fieldLabel' => 'Backup Job Type', 'type' => 'select', 'optionSource' => 'backupJobActions', 'required' => true, 'defaultValue' => 'new'}], options[:options], @api_client)['jobAction']
        if params['jobAction'] == 'new'
          params['jobName'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobName', 'fieldLabel' => 'Job Name', 'type' => 'text', 'required' => false, 'defaultValue' => nil}], options[:options], @api_client)['jobName']
          default_retention_count = (create_results['backup'] && create_results['backup']['retentionCount']) ? create_results['backup']['retentionCount'] : ((create_results['backupSettings'] && create_results['backupSettings']['retentionCount']) ? create_results['backupSettings']['retentionCount'] : nil)
          params['retentionCount'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'retentionCount', 'fieldLabel' => 'Retention Count', 'type' => 'number', 'required' => false, 'defaultValue' => default_retention_count}], options[:options], @api_client)['retentionCount']
          params['jobSchedule'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobSchedule', 'fieldLabel' => 'Backup Schedule', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
            schedules = api_client.options.options_for_source('executeSchedules',{})['data']
            [{"name" => "Manual", "value" => "manual"}] + schedules
          }, 'required' => false}], options[:options], @api_client)['jobSchedule']
          if params['jobSchedule'] == 'manual' || params['jobSchedule'] == ''
            params.delete('jobSchedule')
          end
        elsif params['jobAction'] == 'clone'
          params['jobId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
            @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
              {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
            }
          }, 'required' => true}], options[:options], @api_client)['jobId']
          params['jobName'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobName', 'fieldLabel' => 'Job Name', 'type' => 'text', 'required' => false, 'defaultValue' => nil}], options[:options], @api_client)['jobName']
        elsif params['jobAction'] == 'addTo'
          params['jobId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
            @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
              {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
            }
          }, 'required' => true}], options[:options], @api_client)['jobId']
        end
      end
      payload['backup'].deep_merge!(params)
    end
    execute_api(@backups_interface, :create, [], options, 'backup') do |json_response|
      backup = json_response['backup']
      print_green_success "Added backup #{backup['name']}"
      _get(backup["id"], {}, options)
    end
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[backup] [options]")
      # opts.on('--name NAME', String, "Name") do |val|
      #   options[:options]['name'] = val
      # end
      # opts.on('--job JOB', String, "Name or ID of the Backup Job to associate this backup with") do |val|
      #   options[:options]['jobId'] = val
      # end
      # opts.on('--enabled [on|off]', String, "Can be used to disable") do |val|
      #   options[:options]['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      # end
      build_option_type_options(opts, options, update_backup_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a backup.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup = find_backup_by_name_or_id(args[0])
    return 1 if backup.nil?
    parse_payload(options, 'backup') do |payload|
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_backup_option_types, options[:options], @api_client)
      v_prompt.deep_compact!.booleanize! # remove empty values and convert checkbox "on" and "off" to true and false
      params.deep_merge!(v_prompt)
      payload.deep_merge!({'backup' => params})
      if payload['backup'].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    execute_api(@backups_interface, :update, [backup['id']], options, 'backup') do |json_response|
      backup = json_response['backup']
      print_green_success "Updated backup #{backup['name']}"
      return _get(backup["id"], {}, options)
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[backup] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a backup.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup = find_backup_by_name_or_id(args[0])
    return 1 if backup.nil?
    parse_options(options, params)
    confirm!("Are you sure you want to delete the backup #{backup['name']}?", options)
    execute_api(@backups_interface, :destroy, [backup['id']], options, 'backup') do |json_response|
      print_green_success "Removed backup #{backup['name']}"
    end
  end

  def execute(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[backup] [options]")
      build_standard_post_options(opts, options)
      opts.footer = <<-EOT
Execute a backup to create a new backup result.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup = find_backup_by_name_or_id(args[0])
    return 1 if backup.nil?
    parse_payload(options) do |payload|
    end
    execute_api(@backups_interface, :execute_backup, [backup['id']], options, 'backup') do |json_response|
      print_green_success "Executing backup #{backup['name']}"
      # should get the result maybe, or could even support refreshing until it is complete...
      # return _get(backup["id"], {}, options)
    end
  end

  def restore(args)
    raise "Not Yet Implemented"
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[backup] [result] [options]")
      build_standard_post_options(opts, options)
      opts.on('--result ID', String, "Backup Result ID that is being restored") do |val|
        options[:options]['backupResultId'] = val
      end
      opts.on('--restore-instance existing|new', String, "Instance being targeted for the restore, existing to restore the current instance or new to create a new instance. The current instance is targeted by default.") do |val|
        # restoreInstanceSelect=current|new and the flag on the restore object is called 'restoreToNew'
        options[:options]['restoreInstanceSelect'] = val
      end
      opts.footer = <<-EOT
Restore a backup, replacing the existing target with the specified backup result.
[backup] is required. This is the name or id of a backup.
--result ID is required. This is the id of a backup result being restored.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    connect(options)
    backup = nil
    backup_result = nil
    if args[0]
      backup = find_backup_by_name_or_id(args[0])
      return 1 if backup.nil?
    else
      # Prompt for backup
      if backup.nil?
        # Backup
        available_backups = @backups_interface.list({max:10000})['backups'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        backup_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'backupId', 'fieldLabel' => 'Backup', 'type' => 'select', 'selectOptions' => available_backups, 'required' => true}], options[:options], @api_client)['backupId']
        backup = find_backup_by_name_or_id(backup_id)
      return 1 if backup.nil?
      end
    end
    # Prompt for backup result
    if backup_result.nil?

      # Instance
        available_backup_results = @backups_interface.list({backupId: backup['id'], max:10000})['results'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        params['backupResultId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'backupResultId', 'fieldLabel' => 'Backup Result', 'type' => 'select', 'selectOptions' => available_backup_results, 'required' => true}], options[:options], @api_client)['backupResultId']
        # Name
        params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Backup Name'}], options[:options], @api_client)['name']
    end
    
    parse_payload(options, 'restore') do |payload|
      # Prompt for restore configuration
      # We should probably require identifying the instance by name or id too, just to be safe.
      # Target Instance
      if backup_result['instance']
        params['restoreInstanceSelect'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Instance being targeted for the restore, existing to restore the current instance or new to create a new instance. By default the existing instance is restored.'}], options[:options], @api_client)['restoreInstanceSelect']
      end
      payload['backup'].deep_merge!(params)
    end

    print cyan,"#{bold}WARNING!#{reset}#{cyan} Restoring a backup will erase all data when restored to an existing instance.",reset,"\n"
    confirm!("Are you sure you want to restore the backup result ID: #{backup_result['id']} Name: #{backup_result['backup']['name'] rescue ''} Date: (#{format_local_dt(backup_result['dateCreated'])})?", options)
    execute_api(@backups_interface, :restore, [backup['id']], options, 'backup') do |json_response|
      print_green_success "Restoring backup result ID: #{backup_result['id']} Name: #{backup_result['backup']['name'] rescue ''} Date: (#{format_local_dt(backup_result['dateCreated'])}"
      # should get the restore maybe, or could even support refreshing until it is complete...
      # restore = json_response["restore"]
      # return _get_restore(restore["id"], {}, options)
    end
  end

  # Delegate jobs, results and restores 
  # to backup-jobs, backup-results and backup-restores
  # which are hidden in the docs

  ## Backup Jobs

  def list_jobs(args)
    Morpheus::Cli::BackupJobsCommand.new.list(args)
  end
  
  def get_job(args)
    Morpheus::Cli::BackupJobsCommand.new.get(args)
  end

  def add_job(args)
    Morpheus::Cli::BackupJobsCommand.new.add(args)
  end

  def update_job(args)
    Morpheus::Cli::BackupJobsCommand.new.update(args)
  end

  def remove_job(args)
    Morpheus::Cli::BackupJobsCommand.new.remove(args)
  end

  def execute_job(args)
    Morpheus::Cli::BackupJobsCommand.new.execute(args)
  end

  ## Backup Results

  def list_results(args)
    Morpheus::Cli::BackupResultsCommand.new.list(args)
  end
  
  def get_result(args)
    Morpheus::Cli::BackupResultsCommand.new.get(args)
  end

  def remove_result(args)
    Morpheus::Cli::BackupResultsCommand.new.remove(args)
  end

  ## Backup Restores

  def list_restores(args)
    Morpheus::Cli::BackupRestoresCommand.new.list(args)
  end
  
  def get_restore(args)
    Morpheus::Cli::BackupRestoresCommand.new.get(args)
  end

  def remove_restore(args)
    Morpheus::Cli::BackupRestoresCommand.new.remove(args)
  end

  private

  ## Backups

  def backup_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Backup Job" => lambda {|it| it['job']['name'] rescue '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def backup_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Location Type" => lambda {|it| 
        if it['locationType'] == "instance"
          "Instance"
        elsif it['locationType'] == "server"
          "Host"
        elsif it['locationType'] == "storage"
          "Provider"
        end
      },
      "Instance" => lambda {|it| it['instance']['name'] rescue '' },
      "Container ID" => lambda {|it| it['containerId'] rescue '' },
      "Host" => lambda {|it| it['server']['name'] rescue '' },
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Backup Job" => lambda {|it| it['job']['name'] rescue '' },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  # not used atm, this is not so simple, need to first choose select instance, host or provider
  def add_backup_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'backupType', 'fieldLabel' => 'Backup Type', 'type' => 'select', 'optionSource' => 'backupTypes', 'required' => true},
      {'fieldName' => 'jobAction', 'fieldLabel' => 'Backup Job Type', 'type' => 'select', 'optionSource' => 'backupJobActions', 'required' => true},
      {'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
          {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
        }
      }, 'required' => true},
    ]
  end

  def update_backup_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
      {'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
          {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
        }
      } },
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox'},
    ]
  end

end
