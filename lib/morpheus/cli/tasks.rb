# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Tasks
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :types => :task_types
  alias_subcommand :details, :get
  alias_subcommand :'task-types', :task_types
  set_default_subcommand :list
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @tasks_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).tasks
    @task_sets_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).task_sets
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--types x,y,z', Array, "Filter by task type code(s)") do |val|
        params['taskTypeCodes'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.get(params)
        return
      end
      json_response = @tasks_interface.get(params)
      # print result and return output
      if options[:json]
        puts as_json(json_response, options, "tasks")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['tasks'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "tasks")
        return 0
      else
        title = "Morpheus Tasks"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        tasks = json_response['tasks']
        if tasks.empty?
          print cyan,"No tasks found.",reset,"\n"
        else
          print cyan
          print_tasks_table(tasks, options)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[workflow]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end
  
  def _get(id, options)
    task_name = id
    begin
      @tasks_interface.setopts(options)
      if options[:dry_run]
        if task_name.to_s =~ /\A\d{1,}\Z/
          print_dry_run @tasks_interface.dry.get(task_name.to_i)
        else
          print_dry_run @tasks_interface.dry.get({name: task_name})
        end
        return
      end
      task = find_task_by_name_or_id(task_name)
      exit 1 if task.nil?
      # refetch it
      json_response = {'task' => task}
      unless task_name.to_s =~ /\A\d{1,}\Z/
        json_response = @tasks_interface.get(task['id'])
      end
      if options[:json]
        puts as_json(json_response, options, "task")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "task")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['task']], options)
        return 0
      else
        # load task type to know which options to display
        task_type = task['taskType'] ? find_task_type_by_name(task['taskType']['name']) : nil
        #print "\n", cyan, "Task #{task['name']} - #{task['taskType']['name']}\n\n"
        print_h1 "Task Details"
        print cyan
        description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Code" => 'code',
          "Type" => lambda {|it| it['taskType']['name'] },
          "Execute Target" => lambda {|it| 
            if it['executeTarget'] == 'local'
              git_info = []
              if it['taskOptions']
                if it['taskOptions']['localScriptGitId']
                  git_info << "Git Repo: #{it['taskOptions']['localScriptGitId']}"
                end
                if it['taskOptions']['localScriptGitRef']
                  git_info << "Git Ref: #{it['taskOptions']['localScriptGitRef']}"
                end
              end
              "Local #{git_info.join(', ')}"
            elsif it['executeTarget'] == 'remote'
              remote_url = ""
              if it['taskOptions']
                remote_url = "#{it['taskOptions']['username']}@#{it['taskOptions']['host']}:#{it['taskOptions']['port']}"
              end
              "Remote #{remote_url}"
            elsif it['executeTarget'] == 'resource'
              "Resource"
            else
              it['executeTarget']
            end
          },
          "Result Type" => 'resultType',
          "Retryable" => lambda {|it| 
            if it['retryable']
              format_boolean(it['retryable']).to_s + " Count: #{it['retryCount']}, Delay: #{it['retryDelaySeconds']}" 
            else
              format_boolean(it['retryable'])
            end
          },
        }
        print_description_list(description_cols, task)
        
        # JD: uhh, the api should NOT be returning passwords!!
        if task_type
          task_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
            if optionType['fieldLabel'].to_s.downcase == 'script'
              print_h2 "Script"
              print reset,bright_black,"#{task['taskOptions'][optionType['fieldName']]}","\n",reset
            else
              print cyan,("#{optionType['fieldLabel']} : " + (optionType['type'] == 'password' ? "#{task['taskOptions'][optionType['fieldName']] ? '************' : ''}" : "#{task['taskOptions'][optionType['fieldName']] || optionType['defaultValue']}")),"\n"
            end
          end
        else
          print yellow,"Task type not found.",reset,"\n"
        end
        print reset,"\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[task] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    task_name = args[0]
    connect(options)
    begin


      task = find_task_by_name_or_id(task_name)
      exit 1 if task.nil?
      task_type = find_task_type_by_name(task['taskType']['name'])

      #params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
      params = options[:options] || {}

      if params.empty?
        puts optparse.banner
        option_lines = update_task_option_types(task_type).collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      task_keys = ['name']
      changes_payload = (params.select {|k,v| task_keys.include?(k) })
      task_payload = task
      if changes_payload
        task_payload.merge!(changes_payload)
      end
      if params['taskOptions']
        task_payload['taskOptions'].merge!(params['taskOptions'])
      end

      payload = {task: task_payload}
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.update(task['id'], payload)
        return
      end
      response = @tasks_interface.update(task['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        if !response['success']
          exit 1
        end
      else
        print_green_success "Task #{response['task']['name']} updated"
        get([task['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def task_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.task_types()
        return
      end
      json_response = @tasks_interface.task_types()
      if options[:json]
        print JSON.pretty_generate(json_response),"\n"
      else
        task_types = json_response['taskTypes']
        print_h1 "Morpheus Task Types"
        if task_types.nil? || task_types.empty?
          print yellow,"No task types currently exist on this appliance. This could be a seed issue.",reset,"\n"
        else
          print cyan
          rows = task_types.collect do |task_type|
            {name: task_type['name'], id: task_type['id'], code: task_type['code'], description: task_type['description']}
          end
          puts as_pretty_table(rows, [:id, :name, :code], options)
        end

        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    params = {}
    options = {:options => {}}
    task_name = nil
    task_code = nil
    task_type_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -t TASK_TYPE")
      opts.on( '-t', '--type TASK_TYPE', "Task Type" ) do |val|
        task_type_name = val
      end
      opts.on('--name NAME', String, "Task Name" ) do |val|
        task_name = val
      end
      opts.on('--code CODE', String, "Task Code" ) do |val|
        task_code = val
      end
      opts.on('--result-type VALUE', String, "Result Type" ) do |val|
        options[:options]['resultType'] = val
      end
      opts.on('--result-type VALUE', String, "Result Type" ) do |val|
        options[:options]['executeTarget'] = val
      end
      opts.on('--execute-target VALUE', String, "Execute Target" ) do |val|
        options[:options]['executeTarget'] = val
      end
      opts.on('--target-host VALUE', String, "Target Host" ) do |val|
        options[:options]['taskOptions'] ||= {}
        options[:options]['taskOptions']['host'] = val
      end
      opts.on('--target-port VALUE', String, "Target Port" ) do |val|
        options[:options]['taskOptions'] ||= {}
        options[:options]['taskOptions']['port'] = val
      end
      opts.on('--target-username VALUE', String, "Target Username" ) do |val|
        options[:options]['taskOptions'] ||= {}
        options[:options]['taskOptions']['username'] = val
      end
      opts.on('--target-password VALUE', String, "Target Password" ) do |val|
        options[:options]['taskOptions'] ||= {}
        options[:options]['taskOptions']['password'] = val
      end
      opts.on('--git-repo VALUE', String, "Git Repo ID" ) do |val|
        options[:options]['taskOptions'] ||= {}
        options[:options]['taskOptions']['localScriptGitId'] = val
      end
      opts.on('--git-ref VALUE', String, "Git Ref" ) do |val|
        options[:options]['taskOptions'] ||= {}
        options[:options]['taskOptions']['localScriptGitRef'] = val
      end
      opts.on('--retryable [on|off]', String, "Retryable" ) do |val|
        options[:options]['retryable'] = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--retry-count COUNT', String, "Retry Count" ) do |val|
        options[:options]['retryCount'] = val.to_i
      end
      opts.on('--retry-delay SECONDS', String, "Retry Delay Seconds" ) do |val|
        options[:options]['retryDelaySeconds'] = val.to_i
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --O taskOptions.script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          options[:options]['taskOptions'] ||= {}
          options[:options]['taskOptions']['script'] = File.read(full_filename)
          # params['script'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
        # use the filename as the name by default.
        if !options[:options]['name']
          options[:options]['name'] = File.basename(full_filename)
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      task_name = args[0]
    end
    # if task_name.nil? || task_type_name.nil?
    #   puts optparse
    #   exit 1
    # end
    connect(options)
    begin
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      if passed_options['type']
        task_type_name = passed_options.delete('type')
      end
      payload = nil
      
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'task' => passed_options})  unless passed_options.empty?
      else
        # construct payload
        payload = {
          "task" => {
            #"name" => task_name,
            #"code" => task_code,
            #"taskType" {"id" => task_type['id'], "code" => task_type['code']},
            #"taskOptions" => {}
          }
        }
        payload.deep_merge!({'task' => passed_options})  unless passed_options.empty?

        
        
        # Name
        if task_name
          payload['task']['name'] = task_name
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name'}], options[:options], @api_client)
          payload['task']['name'] = v_prompt['name'] unless v_prompt['name'].to_s.empty?
        end

        # Code
        if task_code
          payload['task']['code'] = task_code
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'description' => 'Code'}], options[:options], @api_client)
          payload['task']['code'] = v_prompt['code'] unless v_prompt['code'].to_s.empty?
        end

        # Task Type
        @all_task_types ||= @tasks_interface.task_types({max:1000})['taskTypes']
        task_types_dropdown = @all_task_types.collect {|it| {"name" => it["name"], "value" => it["code"]}}
        
        if task_type_name
          #payload['task']['taskType'] = task_type_name
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => task_types_dropdown, 'required' => true}], options[:options], @api_client)
          task_type_name = v_prompt['type']
        end

        task_type = find_task_type_by_name(task_type_name)
        if task_type.nil?
          print_red_alert "Task Type not found by code '#{task_type_name}'"
          return 1
        end

        payload['task']['taskType'] = {"id" => task_type['id'], "code" => task_type['code']}


        # Result Type
        if options[:options]['resultType']
          payload['task']['resultType'] = options[:options]['resultType']
        else
          result_types_dropdown = [{"name" => "Value", "value" => "value"}, {"name" => "Exit Code", "value" => "exitCode"}, {"name" => "Key Value", "value" => "keyValue"}, {"name" => "JSON", "value" => "json"}]
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'resultType', 'fieldLabel' => 'Result Type', 'type' => 'select', 'selectOptions' => result_types_dropdown}], options[:options], @api_client)
          payload['task']['resultType'] = v_prompt['resultType'] unless v_prompt['resultType'].to_s.empty?
        end

        # Task Type Option Types

        # JD: uhh some of these are missing a fieldContext?
        # containerScript just points to a library script  via Id now??
        task_option_types = task_type['optionTypes'] || []
        task_option_types.each do |it|
          if it['fieldContext'].nil? || it['fieldContext'] == ''
            it['fieldContext'] = 'taskOptions'
          end
        end
        input_options = Morpheus::Cli::OptionTypes.prompt(task_option_types, options[:options],@api_client, options[:params])
        payload.deep_merge!({'task' => input_options})  unless input_options.empty?
        

        # Target Options

        if options[:options]['executeTarget'] != nil
          payload['task']['executeTarget'] = options[:options]['executeTarget']
        else
          default_target = nil
          execute_targets_dropdown = []
          if task_type['allowExecuteLocal']
            default_target = 'local'
            execute_targets_dropdown << {"name" => "Local", "value" => "local"}
          end
          if task_type['allowExecuteRemote']
            default_target = 'remote'
            execute_targets_dropdown << {"name" => "Remote", "value" => "remote"}
          end
          if task_type['allowExecuteResource']
            default_target = 'resource'
            execute_targets_dropdown << {"name" => "Resource", "value" => "resource"}
          end
          if !execute_targets_dropdown.empty?
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'executeTarget', 'fieldLabel' => 'Execute Target', 'type' => 'select', 'selectOptions' => execute_targets_dropdown, 'defaultValue' => default_target}], options[:options], @api_client)
            payload['task']['executeTarget'] = v_prompt['executeTarget'].to_s unless v_prompt['executeTarget'].to_s.empty?
          end
        end

        if payload['task']['executeTarget'] == 'local'
          # Git Repo
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'taskOptions', 'fieldName' => 'localScriptGitId', 'fieldLabel' => 'Git Repo', 'type' => 'text', 'description' => 'Git Repo ID'}], options[:options], @api_client)
          if v_prompt['taskOptions'] && !v_prompt['taskOptions']['localScriptGitId'].to_s.empty?
            payload['task']['taskOptions'] ||= {}
            payload['task']['taskOptions']['localScriptGitId'] = v_prompt['taskOptions']['localScriptGitId']
          end
          # Git Ref
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'taskOptions', 'fieldName' => 'localScriptGitRef', 'fieldLabel' => 'Git Ref', 'type' => 'text', 'description' => 'Git Ref eg. master'}], options[:options], @api_client)
          if v_prompt['taskOptions'] && !v_prompt['taskOptions']['localScriptGitRef'].to_s.empty?
            payload['task']['taskOptions'] ||= {}
            payload['task']['taskOptions']['localScriptGitRef'] = v_prompt['taskOptions']['localScriptGitRef']
          end

        elsif payload['task']['executeTarget'] == 'remote'
          # Host
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'taskOptions', 'fieldName' => 'host', 'fieldLabel' => 'IP Address', 'type' => 'text', 'description' => 'IP Address / Host for remote execution'}], options[:options], @api_client)
          if v_prompt['taskOptions'] && !v_prompt['taskOptions']['host'].to_s.empty?
            payload['task']['taskOptions'] ||= {}
            payload['task']['taskOptions']['host'] = v_prompt['taskOptions']['host']
          end
          # Port
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'taskOptions', 'fieldName' => 'port', 'fieldLabel' => 'Port', 'type' => 'text', 'description' => 'Port for remote execution', 'defaultValue' => '22'}], options[:options], @api_client)
          if v_prompt['taskOptions'] && !v_prompt['taskOptions']['port'].to_s.empty?
            payload['task']['taskOptions'] ||= {}
            payload['task']['taskOptions']['port'] = v_prompt['taskOptions']['port']
          end
          # Host
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'taskOptions', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'description' => 'Username for remote execution'}], options[:options], @api_client)
          if v_prompt['taskOptions'] && !v_prompt['taskOptions']['username'].to_s.empty?
            payload['task']['taskOptions'] ||= {}
            payload['task']['taskOptions']['username'] = v_prompt['taskOptions']['username']
          end
          # Host
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'taskOptions', 'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'description' => 'Password for remote execution'}], options[:options], @api_client)
          if v_prompt['taskOptions'] && !v_prompt['taskOptions']['password'].to_s.empty?
            payload['task']['taskOptions'] ||= {}
            payload['task']['taskOptions']['password'] = v_prompt['taskOptions']['password']
          end
        end


        # Retryable
        if options[:options]['retryable'] != nil
          payload['task']['retryable'] = options[:options]['retryable']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'retryable', 'fieldLabel' => 'Retryable', 'type' => 'checkbox', 'defaultValue' => false}], options[:options], @api_client)
          payload['task']['retryable'] = ['true','on'].include?(v_prompt['retryable'].to_s) unless v_prompt['retryable'].nil?
        end

        if payload['task']['retryable']
          # Retry Count
          if options[:options]['retryCount']
            payload['task']['retryCount'] = options[:options]['retryCount'].to_i
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'retryCount', 'fieldLabel' => 'Retry Count', 'type' => 'number', 'defaultValue' => 5}], options[:options], @api_client)
            payload['task']['retryCount'] = v_prompt['retryCount'].to_i unless v_prompt['retryCount'].nil?
          end
          # Retry Delay
          if options[:options]['retryDelay']
            payload['task']['retryDelay'] = options[:options]['retryDelay'].to_i
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'retryDelay', 'fieldLabel' => 'Retry Delay', 'type' => 'number', 'defaultValue' => 10}], options[:options], @api_client)
            payload['task']['retryDelay'] = v_prompt['retryDelay'].to_i unless v_prompt['retryDelay'].nil?
          end
        end


       

      end
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.create(payload)
        return
      end
      json_response = @tasks_interface.create(payload)
      task = json_response['task']
      if options[:json]
        print JSON.pretty_generate(json_response),"\n"
      elsif !options[:quiet]
        task = json_response['task']
        print_green_success "Task #{task['name']} created successfully"
        get([task['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    params = {}
    task_name = args[0]
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[task]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.on( '-f', '--force', "Force Delete" ) do
        params[:force] = true
      end
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      task = find_task_by_name_or_id(task_name)
      exit 1 if task.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the task #{task['name']}?")
        exit
      end
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.destroy(task['id'], params)
        return
      end
      json_response = @tasks_interface.destroy(task['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response),"\n"
      elsif !options[:quiet]
        print_green_success "Task #{task['name']} removed"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private
  def find_task_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_task_by_id(val)
    else
      return find_task_by_name(val)
    end
  end

  def find_task_by_id(id)
    begin
      json_response = @tasks_interface.get(id.to_i)
      return json_response['task']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Task not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_task_by_name(name)
    tasks = @tasks_interface.get({name: name.to_s})['tasks']
    if tasks.empty?
      print_red_alert "Task not found by name #{name}"
      return nil
    elsif tasks.size > 1
      print_red_alert "#{tasks.size} tasks by name #{name}"
      print_tasks_table(tasks, {color: red})
      print reset,"\n\n"
      return nil
    else
      return tasks[0]
    end
  end

  def find_task_type_by_name(val)
    raise "find_task_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
    @all_task_types ||= @tasks_interface.task_types({max:1000})['taskTypes']

    if @all_task_types.nil? && !@all_task_types.empty?
      print_red_alert "No task types found"
      return nil
    end
    matching_task_types = @all_task_types.select { |it| val && (it['name'] == val || it['code'] == val ||  it['id'].to_s == val.to_s) }
    if matching_task_types.size == 1
      return matching_task_types[0]
    elsif matching_task_types.size == 0
      print_red_alert "Task Type not found by '#{val}'"
    else
      print_red_alert "#{matching_task_types.size} task types found by name #{name}"
      rows = matching_task_types.collect do |it|
        {id: it['id'], name: it['name'], code: it['code']}
      end
      print "\n"
      puts as_pretty_table(rows, [:name, :code], {color:red})
      return nil
    end
  end

  def update_task_option_types(task_type)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 0}
    ] + task_type['optionTypes']
  end

  def print_tasks_table(tasks, opts={})
    columns = [
      {"ID" => lambda {|it| it['id'] } },
      {"NAME" => lambda {|it| it['name'] } },
      {"TYPE" => lambda {|it| it['taskType']['name'] ? it['taskType']['name'] : it['type'] } },
      # {"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
      # {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(tasks, columns, opts)
  end

end
