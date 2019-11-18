require 'morpheus/cli/cli_command'

class Morpheus::Cli::JobsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'jobs'

  register_subcommands :list, :get, :add, :update, :execute, :remove
  register_subcommands :list_executions, :get_execution
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @jobs_interface = @api_client.jobs
    @options_interface = @api_client.options
    @tasks_interface = @api_client.tasks
    @task_sets_interface = @api_client.task_sets
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
    @containers_interface = @api_client.containers
    @execute_schedules_interface = @api_client.execute_schedules
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List jobs."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      params.merge!(parse_list_options(options))
      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.list(params)
        return
      end
      json_response = @jobs_interface.list(params)

      render_result = render_with_format(json_response, options, 'jobs')
      return 0 if render_result

      title = "Morpheus Jobs"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      jobs = json_response['jobs']

      if jobs.empty?
        print yellow,"No jobs found.",reset,"\n"
      else
        rows = jobs.collect do |job|
          {
              id: job['id'],
              type: job['type'] ? job['type']['name'] : '',
              name: job['name'],
              details: job['jobSummary'],
              enabled: "#{job['enabled'] ? '' : yellow}#{format_boolean(job['enabled'])}",
              lastRun: format_local_dt(job['lastRun']),
              nextRun: job['enabled'] && job['scheduleMode'] && job['scheduleMode'] != 'manual' ? format_local_dt(job['nextFire']) : '',
              lastResult: format_status(job['lastResult'])
          }
        end
        columns = [
            :id, :type, :name, :details, :enabled, :lastRun, :nextRun, :lastResult
        ]
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)

        if stats = json_response['stats']
          label_width = 17

          print_h2 "Executions Stats - Last 7 Days"
          print cyan

          print "Jobs".rjust(label_width, ' ') + ": #{stats['jobCount']}\n"
          print "Executions Today".rjust(label_width, ' ') + ": #{stats['todayCount']}\n"
          print "Daily Executions".rjust(label_width, ' ') + ": " + stats['executionsPerDay'].join(' | ') + "\n"
          print "Total Executions".rjust(label_width, ' ') + ": #{stats['execCount']}\n"
          print "Completed".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['execSuccessRate'].to_f, 100) + "#{stats['execSuccess']}".rjust(15, ' ') + " of " + "#{stats['execCount']}".ljust(15, ' ') + "\n#{cyan}"
          print "Failed".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['execFailedRate'].to_f, 100) + "#{stats['execFailed']}".rjust(15, ' ') + " of " + "#{stats['execCount']}".ljust(15, ' ') + "\n#{cyan}"
        end
        print reset,"\n"
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[job] [max-exec-count]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a job.\n" +
          "[job] is required. Job ID or name.\n" +
          "[max-exec-count] is optional. Specified max # of most recent executions. Defaults is 3"
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    return _get(args[0], args.count > 1 ? args[1] : nil, options)
  end

  def _get(job_id, max_execs = 3, options = {})
    begin
      @jobs_interface.setopts(options)

      if !(job_id.to_s =~ /\A\d{1,}\Z/)
        job = find_by_name_or_id('job', job_id)

        if !job
          print_red_alert "Job #{job_id} not found"
          exit 1
        end
        job_id = job['id']
      end

      max_execs = 3 if max_execs.nil?

      params = {'includeExecCount' => max_execs}

      if options[:dry_run]
        print_dry_run @jobs_interface.dry.get(job_id, params)
        return
      end
      json_response = @jobs_interface.get(job_id, params)

      render_result = render_with_format(json_response, options, 'job')
      return 0 if render_result

      title = "Morpheus Job"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      job = json_response['job']
      scheduleName = ''
      if job['scheduleMode'] == 'manual'
        scheduleName = 'Manual'
      else
        schedule = @execute_schedules_interface.get(job['scheduleMode'])['schedule']
        scheduleName = schedule ? schedule['name'] : ''
      end

      print cyan
      description_cols = {
          "Name" => lambda {|it| it['name']},
          "Job Type" => lambda {|it| it['type']['name']},
          "Enabled" => lambda {|it| format_boolean(it['enabled'])},
          (job['workflow'] ? 'Workflow' : 'Task') => lambda {|it| it['jobSummary']},
          "Schedule" => lambda {|it| scheduleName}
      }

      if job['targetType']
        description_cols["Context Type"] = lambda {|it| it['targetType'] == 'appliance' ? 'None' : it['targetType'] }

        if job['targetType'] != 'appliance'
          description_cols["Context #{job['targetType'].capitalize}#{job['targets'].count > 1 ? 's' : ''}"] = lambda {|it| it['targets'].collect {|it| it['name']}.join(', ')}
        end
      end

      print_description_list(description_cols, job)

      if max_execs != 0
        print_h2 "Recent Executions"
        print_job_executions(json_response['executions']['jobExecutions'], options)

        if json_response['executions']['meta'] && json_response['executions']['meta']['total'] > max_execs
          print_results_pagination(json_response['executions'])
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[name]")
      opts.on("--name NAME", String, "Updates job name") do |val|
        params['name'] = val.to_s
      end
      opts.on('-a', '--active [on|off]', String, "Can be used to enable / disable the job. Default is on") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-t', '--task [TASK]', String, "Task ID or code, assigns task to job. Incompatible with --workflow option.") do |val|
        if options[:workflow].nil?
          options[:task] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('-w', '--workflow [WORKFLOW]', String, "Workflow ID or code, assigns workflow to job. Incompatible with --task option.") do |val|
        if options[:task].nil?
          options[:workflow] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('--context-type [TYPE]', String, "Context type (instance|server|none). Default is none") do |val|
        params['targetType'] = (val == 'none' ? 'appliance' : val)
      end
      opts.on('--instances [LIST]', Array, "Context instances(s), comma separated list of instance IDs. Incompatible with --servers") do |list|
        params['targetType'] = 'instance'
        params['targets'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('--servers [LIST]', Array, "Context server(s), comma separated list of server IDs. Incompatible with --instances") do |list|
        params['targetType'] = 'server'
        params['targets'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('-S', '--schedule [SCHEDULE]', String, "Job execution schedule type name or ID") do |val|
        options[:schedule] = val
      end
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      opts.on('-R', '--run [on|off]', String, "Can be used to run the job now.") do |val|
        params['run'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create job."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0 or 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)

      if !payload
        # name
        params['name'] = params['name'] || args[0] || name = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Job Name', 'required' => true, 'description' => 'Job Name.'}],options[:options],@api_client,{})['name']

        if options[:task].nil? && options[:workflow].nil?
          # prompt job type
          job_types = @options_interface.options_for_source('jobTypes', {})['data']
          job_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobType', 'type' => 'select', 'fieldLabel' => 'Job Type', 'selectOptions' => job_types, 'required' => true, 'description' => 'Select Job Type.'}],options[:options],@api_client,{})['jobType']
          job_type = job_types.find {|it| it['value'] == job_type_id}

          job_options = @jobs_interface.options(job_type_id)

          # prompt task / workflow
          if job_type['code'] == 'morpheus.task'
            task_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'task', 'fieldLabel' => 'Task', 'type' => 'select', 'required' => true, 'optionSource' => 'tasks'}], {'optionTypeId' => job_options['optionTypes'][0]['id']}, @api_client, {})['task']
            params['task'] = {'id' => task_id}
          else
            workflow_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'workflow', 'fieldLabel' => 'Workflow', 'type' => 'select', 'required' => true, 'optionSource' => 'operationTaskSets'}], {'optionTypeId' => job_options['optionTypes'][0]['id']}, @api_client, {})['workflow']
            params['workflow'] = {'id' => workflow_id}
          end
        end

        # task
        if !options[:task].nil?
          task = find_by_name_or_id('task', options[:task])

          if task.nil?
            print_red_alert "Task #{options[:task]} not found"
            exit 1
          end
          params['task'] = {'id' => task['id']}
          job_type_id = load_job_type_id_by_code('morpheus.task')
        end

        # workflow
        if !options[:workflow].nil?
          task_set = find_by_name_or_id('task_set', options[:workflow])

          if task_set.nil?
            print_red_alert "Workflow #{options[:workflow]} not found"
            exit 1
          end
          params['workflow'] = {'id' => task_set['id']}
          job_type_id = load_job_type_id_by_code('morpheus.workflow')
        end

        # load options based upon job type + task / taskset
        job_options = @jobs_interface.options(job_type_id, {'taskId' => params['task'] ? params['task']['id'] : nil, 'workflowId' => params['workflow'] ? params['workflow']['id'] : nil})
        option_type_id = job_options['optionTypes'][0]['id']

        # context type
        if params['targetType'].nil?
          params['targetType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'contextType', 'fieldLabel' => 'Context Type', 'type' => 'select', 'required' => true, 'selectOptions' => job_options['targetTypes'], 'defaultValue' => job_options['targetTypes'].first['name']}], {'optionTypeId' => option_type_id}, @api_client, {})['contextType']
        end

        # contexts
        if ['instance', 'server'].include?(params['targetType']) && (params['targets'].nil? || params['targets'].empty?)
          targets = []
          if params['targetType'] == 'instance'
            avail_targets = @instances_interface.list()['instances'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
          else
            avail_targets = @servers_interface.list({'vmHypervisor' => nil, 'containerHypervisor' => nil})['servers'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
          end
          target_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'target', 'fieldLabel' => "Context #{params['targetType'].capitalize}", 'type' => 'select', 'required' => true, 'selectOptions' => avail_targets}], options[:options], @api_client, {}, options[:no_prompt], true)['target']
          targets << target_id
          avail_targets.reject! {|it| it['value'] == target_id}

          while !target_id.nil? && !avail_targets.empty? && Morpheus::Cli::OptionTypes.confirm("Add another context #{params['targetType']}?", {:default => false})
            target_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'target', 'fieldLabel' => "Context #{params['targetType'].capitalize}", 'type' => 'select', 'required' => false, 'selectOptions' => avail_targets}], options[:options], @api_client, {}, options[:no_prompt], true)['target']

            if !target_id.nil?
              targets << target_id
              avail_targets.reject! {|it| it['value'] == target_id}
            end
          end
          params['targets'] = targets.collect {|it| {'refId' => it}}
        end

        # schedule
        if options[:schedule].nil?
          params['scheduleMode'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'schedule', 'fieldLabel' => "Schedule", 'type' => 'select', 'required' => true, 'selectOptions' => job_options['schedules'], 'defaultValue' => job_options['schedules'].first['name']}], options[:options], @api_client, {})['schedule']
        else
          if options[:schedule] != 'manual'
            schedule = job_options['schedules'].find {|it| it['name'] == options[:schedule] || it['value'] == options[:schedule].to_i}

            if schedule.nil?
              print_red_alert "Schedule #{options[:schedule]} not found"
              exit 1
            end
            options[:schedule] = schedule['value']
          end
          params['scheduleMode'] = options[:schedule]
        end

        # custom config
        if params['customConfig'].nil? && job_options['allowCustomConfig']
          params['customConfig'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'config', 'fieldLabel' => "Custom Config", 'type' => 'text', 'required' => false}], options[:options], @api_client, {})['config']
        end
        payload = {'job' => params}
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.create(payload)
        return
      end
      json_response = @jobs_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Job created"
          _get(json_response['id'], 0, options)
        else
          print_red_alert "Error creating job: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[job]")
      opts.on("--name NAME", String, "Updates job name") do |val|
        params['name'] = val.to_s
      end
      opts.on('-a', '--active [on|off]', String, "Can be used to enable / disable the job. Default is on") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-t', '--task [TASK]', String, "Task ID or code, assigns task to job. Incompatible with --workflow option.") do |val|
        if options[:workflow].nil?
          options[:task] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('-w', '--workflow [WORKFLOW]', String, "Workflow ID or code, assigns workflow to job. Incompatible with --task option.") do |val|
        if options[:task].nil?
          options[:workflow] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('--context-type [TYPE]', String, "Context type (instance|server|none). Default is none") do |val|
        params['targetType'] = (val == 'none' ? 'appliance' : val)
      end
      opts.on('--instances [LIST]', Array, "Context instances(s), comma separated list of instance IDs. Incompatible with --servers") do |list|
        params['targetType'] = 'instance'
        options[:targets] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip.to_i }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('--servers [LIST]', Array, "Context server(s), comma separated list of server IDs. Incompatible with --instances") do |list|
        params['targetType'] = 'server'
        options[:targets] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip.to_i }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('--schedule [SCHEDULE]', String, "Job execution schedule type name or ID") do |val|
        options[:schedule] = val
      end
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      opts.on('-R', '--run [on|off]', String, "Can be used to run the job now.") do |val|
        params['run'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_common_options(opts, options, [:payload, :list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Update job.\n" +
          "[job] is required. Job ID or name"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      job = find_by_name_or_id('job', args[0])

      if job.nil?
        print_red_alert "Job #{args[0]} not found"
        exit 1
      end

      payload = parse_payload(options)

      if !payload
        job_type_id = job['type']['id']

        if !options[:task].nil?
          task = find_by_name_or_id('task', options[:task])

          if task.nil?
            print_red_alert "Task #{options[:task]} not found"
            exit 1
          end
          params['task'] = {'id': task['id']}
          job_type_id = load_job_type_id_by_code('morpheus.task')
        end

        if !options[:workflow].nil?
          task_set = find_by_name_or_id('task_set', options[:workflow])

          if task_set.nil?
            print_red_alert "Workflow #{options[:workflow]} not found"
            exit 1
          end
          params['workflow'] = {'id': task_set['id']}
          job_type_id = load_job_type_id_by_code('morpheus.workflow')
        end

        if !options[:targets].nil? && ['instance', 'server'].include?(params['targetType'])
          params['targets'] = []
          target_type = params['targetType'] || job['targetType']
          options[:targets].collect do |it|
            target = find_by_name_or_id(target_type, it['refId'])

            if target.nil?
              print_red_alert "Context #{target_type} #{it['refId']} not found"
              exit 1
            end
            params['targets'] << it
          end
        end

        if !options[:schedule].nil?
          if options[:schedule] != 'manual'
            job_options = @jobs_interface.options(job_type_id)
            schedule = job_options['schedules'].find {|it| it['name'] == options[:schedule] || it['value'] == options[:schedule].to_i}

            if schedule.nil?
              print_red_alert "Schedule #{options[:schedule]} not found"
              exit 1
            end
            options[:schedule] = schedule['value']
          end
          params['scheduleMode'] = options[:schedule]
        end
        payload = {'job' => params}
      end

      if payload['job'].nil? || payload['job'].empty?
        print_green_success "Nothing to update"
        exit 1
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.update(job['id'], payload)
        return
      end
      json_response = @jobs_interface.update(job['id'], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Job updated"
          _get(job['id'], nil, options)
        else
          print_red_alert "Error updating job: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def execute(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[job]")
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Run job.\n" +
          "[job] is required. Job ID or name"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      job = find_by_name_or_id('job', args[0])

      if job.nil?
        print_red_alert "Job #{args[0]} not found"
        exit 1
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.execute_job(job['id'], params)
        return
      end

      json_response = @jobs_interface.execute_job(job['id'], params)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Job queued for execution"
          _get(job['id'], nil, options)
        else
          print_red_alert "Error executing job: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[job]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Remove job.\n" +
          "[job] is required. Job ID or name"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      job = find_by_name_or_id('job', args[0])

      if job.nil?
        print_red_alert "Job #{args[0]} not found"
        exit 1
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.destroy(job['id'], params)
        return
      end

      json_response = @jobs_interface.destroy(job['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Job #{job['name']} removed"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_executions(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-J', '--job [job]', String, "Job Id or name. Show executions for specified job") do |val|
        options[:job] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List job executions."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      params.merge!(parse_list_options(options))

      if !options[:job].nil?
        job = find_by_name_or_id('job', options[:job])

        if job.nil?
          print_red_alert "Job #{options[:job]} not found"
          exit 1
        end
        params['jobId'] = job['id']
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.list_executions(params)
        return
      end
      json_response = @jobs_interface.list_executions(params)

      render_result = render_with_format(json_response, options, 'jobExecutions')
      return 0 if render_result

      title = "Morpheus Job Executions"
      subtitles = job ? ["Job: #{job['name']}"] : []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      print_job_executions(json_response['jobExecutions'], options)
      print_results_pagination(json_response)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_execution(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a job.\n" +
          "[id] is required. Job execution ID."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      @jobs_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @jobs_interface.dry.get_execution(args[0], params)
        return
      end
      json_response = @jobs_interface.get_execution(args[0], params)

      render_result = render_with_format(json_response, options, 'job')
      return 0 if render_result

      title = "Morpheus Job Execution"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      exec = json_response['jobExecution']
      print cyan
      description_cols = {
          "Job" => lambda {|it| it['job']['name']},
          "Job Type" => lambda {|it| it['job']['type']['name']},
          "Description" => lambda {|it| it['process']['description'] || it['process']['refType'] == 'instance' ? it['process']['displayName'] : it['process']['processTypeName'].capitalize },
          "Start Date" => lambda {|it| format_local_dt(it['startDate'])},
          "Created By" => lambda {|it| it['process']['createdBy'] ? it['process']['createdBy']['displayName'] : ''},
          (['complete', 'failed'].include?(exec['process']['status']) ? "Duration" : "ETA") => lambda {|it| (it['process']['duration'] || it['process']['statusEta']) ? format_human_duration((it['process']['duration'] || it['process']['statusEta']) / 1000.0) : ''},
          "Status" => lambda {|it| it['status']}
      }

      if exec['process']['output']
        description_cols['Process Output'] = lambda {|it| it['process']['output']}
      elsif exec['process']['message'] || exec['process']['error']
        description_cols['Errors'] = lambda {|it| it['process']['message'] || it['process']['error']}
      end

      print_description_list(description_cols, exec)

      if !exec['process']['events'].empty?
        print_h2 "Sub Processes"
        print_process_events(exec['process']['events'])
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def print_process_events(events, options={})
    rows = events.collect do |evt|
      {
          id: evt['id'],
          description: evt['description'] || evt['processTypeName'],
          startDate: format_local_dt(evt['startDate']),
          duration: format_human_duration((evt['duration'] || evt['statusEta'] || 0) / 1000.0),
          error: evt['message']
      }
    end
    columns = [
        :id, :description, :startDate, :duration, :error
    ]
    print as_pretty_table(rows, columns, options)
    print reset,"\n"
  end

  def print_job_executions(execs, options={})
    if execs.empty?
      print yellow,"No job executions found.",reset,"\n"
    else
      rows = execs.collect do |ex|
        {
            id: ex['id'],
            name: ex['job'] ? ex['job']['name'] : '',
            type: ex['job'] ? (ex['job']['type']['code'] == 'morpheus.workflow' ? 'Workflow' : 'Task') : '',
            startDate: format_local_dt(ex['startDate']),
            duration: ex['duration'] ? format_human_duration(ex['duration'] / 1000.0) : '',
            status: format_status(ex['status']),
            error: truncate_string(ex['process'] && (ex['process']['message'] || ex['process']['error']) ? ex['process']['message'] || ex['process']['error'] : '', 32)
        }
      end
      columns = [
          :id, :name, :type, :startDate, :duration, :status, :error
      ]
      print as_pretty_table(rows, columns, options)
      print reset,"\n"
    end
  end

  def format_status(status_string, return_color=cyan)
    out = ""
    if status_string
      if ['success', 'successful', 'ok'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      elsif ['error', 'offline', 'failed', 'failure'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{yellow}#{status_string.upcase}"
      end
    end
    out + return_color
  end

  def find_by_name_or_id(type, val)
    interface = instance_variable_get "@#{type}s_interface"
    typeCamelCase = type.gsub(/(?:^|_)([a-z])/) do $1.upcase end
    typeCamelCase = typeCamelCase[0, 1].downcase + typeCamelCase[1..-1]
    (val.to_s =~ /\A\d{1,}\Z/) ? interface.get(val.to_i)[typeCamelCase] : interface.list({'name' => val})["#{typeCamelCase}s"].first
  end

  def load_job_type_id_by_code(code)
    @options_interface.options_for_source('jobTypes', {})['data'].find {|it| it['code'] == code}['value'] rescue nil
  end
end
