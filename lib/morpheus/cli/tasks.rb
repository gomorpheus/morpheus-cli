# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Tasks
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :execute
  register_subcommands :'list-types' => :list_task_types
  register_subcommands :'get-type' => :get_task_type
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @tasks_interface = @api_client.tasks
    @task_sets_interface = @api_client.task_sets
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-t', '--type x,y,z', Array, "Filter by task type code(s)") do |val|
        params['taskTypeCodes'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.list(params)
        return
      end
      json_response = @tasks_interface.list(params)

      render_result = render_with_format(json_response, options, 'tasks')
      return 0 if render_result
      
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
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[workflow]")
      opts.on('--no-content', "Do not display script content." ) do
        options[:no_content] = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
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
          "Allow Custom Config" => lambda {|it| format_boolean(it['allowCustomConfig']) },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }
        print_description_list(description_cols, task)
        
        # JD: uhh, the api should NOT be returning passwords!!
        if task_type
          # task_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
          #   if optionType['fieldLabel'].to_s.downcase == 'script'
          #     if task['taskOptions'][optionType['fieldName']]
          #       print_h2 "Script"
          #       print reset,"#{task['taskOptions'][optionType['fieldName']]}","\n",reset
          #     end
          #   else
          #     print cyan,("#{optionType['fieldLabel']} : " + (optionType['type'] == 'password' ? "#{task['taskOptions'][optionType['fieldName']] ? '************' : ''}" : "#{task['taskOptions'][optionType['fieldName']] || optionType['defaultValue']}")),"\n"
          #   end
          # end
          script_content = nil
          task_option_types = []
          task_option_config = {}
          task_option_columns = []
          task_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
            if optionType['fieldLabel'].to_s.downcase == 'script'
              script_content = task['taskOptions'][optionType['fieldName']]
            elsif optionType['fieldName'] == 'httpHeaders' || optionType['fieldName'] == 'webHeaders'
              http_headers = task['taskOptions']['httpHeaders'] || task['taskOptions']['webHeaders']
              begin
                if http_headers.is_a?(String)
                  http_headers = JSON.parse(http_headers)
                end
                # API has mismatch on fieldName httpHeaders vs webHeaders, we want to format this in a particular way though anyhow..
                task_option_columns << {(optionType['fieldLabel']) => lambda {|it| http_headers.collect {|h| "#{h['key']}: #{h['value']}"}.join(", ") } }
              rescue => ex
                Morpheus::Logging::DarkPrinter.puts("Failed to parse httpHeaders task option as JSON") if Morpheus::Logging.debug?
              end
            else
              task_option_types << optionType
              task_option_columns << {(optionType['fieldLabel']) => lambda {|it| task['taskOptions'][optionType['fieldName']] || optionType['defaultValue'] } }
            end
          end
        else
          print yellow,"Task type not found.",reset,"\n"
        end
        if !task_option_columns.empty?
          print_h2 "Task Options"
          print_description_list(task_option_columns, task["taskOptions"])
        end
        if script_content
          print_h2 "Script"
          print reset,script_content,"\n",reset
        end
        # some task types have a file (file-content) instead of taskOptions.script
        file_content = task['file']
        if file_content && options[:no_content] != true
          print_h2 "Script Content"
          if file_content['sourceType'] == 'local'
            puts file_content['content']
          elsif file_content['sourceType'] == 'url'
            puts "URL: #{file_content['contentPath']}"
          elsif file_content['sourceType'] == 'repository'
            puts "Repository: #{file_content['repository']['name'] rescue 'n/a'}"
            puts "Path: #{file_content['contentPath']}"
            if file_content['contentRef']
              puts "Ref: #{file_content['contentRef']}"
            end
          else
            puts "Source: #{file_content['sourceType']}"
            puts "Path: #{file_content['contentPath']}"
          end
        end

        print reset,"\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    params = {}
    file_params = {}
    options = {}
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
      opts.on('--source VALUE', String, "Source Type. local, repository, url. Only applies to script task types.") do |val|
        file_params['sourceType'] = val
      end
      opts.on('--content TEXT', String, "Contents of the task script. This implies source is local.") do |val|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        file_params['content'] = val
      end
      opts.on('--file FILE', "File containing the task script. This can be used instead of --content" ) do |filename|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          file_params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on('--url VALUE', String, "URL, for use when source is url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-path VALUE', String, "Content Path, for use when source is repository or url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-ref VALUE', String, "Content Ref (Version Ref), for use when source is repository") do |val|
        file_params['contentRef'] = val
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
      opts.on('--allow-custom-config [on|off]', String, "Allow Custom Config") do |val|
        options[:options]['allowCustomConfig'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
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
        payload.deep_merge!({'task' => {'file' => file_params}}) unless file_params.empty?
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
        @all_task_types ||= @tasks_interface.list_types({max:1000})['taskTypes']
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

        # correct fieldContext
        has_file_content = false
        task_option_types = task_type['optionTypes'] || []
        task_option_types.each do |it|
          if it['type'] == 'file-content'
            has_file_content = true
            it['fieldContext'] = nil
            it['fieldName'] = 'file'
          else
            if it['fieldContext'].nil? || it['fieldContext'] == ''
              it['fieldContext'] = 'taskOptions'
            end
          end
        end
        # inject file_params into options for file-content prompt
        # or into taskOptions.script for types not yet using file-content
        unless file_params.empty?
          if has_file_content
            options[:options]['file'] ||= {}
            options[:options]['file'].merge!(file_params)
          else
            options[:options]['taskOptions'] ||= {}
            options[:options]['taskOptions']['script'] = file_params['content'] if file_params['content']
          end
        end
        # prompt
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
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'executeTarget', 'fieldLabel' => 'Execute Target', 'type' => 'select', 'selectOptions' => execute_targets_dropdown, 'defaultValue' => default_target, 'required' => true}], options[:options], @api_client)
            payload['task']['executeTarget'] = v_prompt['executeTarget'].to_s unless v_prompt['executeTarget'].to_s.empty?
          end
        end

        if payload['task']['executeTarget'] == 'local'
          if task_type['allowLocalRepo']
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


        # Allow Custom Config
        if options[:options]['allowCustomConfig'] != nil
          payload['task']['allowCustomConfig'] = options[:options]['allowCustomConfig']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allowCustomConfig', 'fieldLabel' => 'Allow Custom Config', 'type' => 'checkbox', 'defaultValue' => false}], options[:options], @api_client)
          payload['task']['allowCustomConfig'] = ['true','on'].include?(v_prompt['allowCustomConfig'].to_s) unless v_prompt['allowCustomConfig'].nil?
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
        print_green_success "Task #{task['name']} created"
        get([task['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    params = {}
    file_params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[task] [options]")
      opts.on('--name NAME', String, "Task Name" ) do |val|
        options[:options]['name'] = val
      end
      opts.on('--code CODE', String, "Task Code" ) do |val|
        options[:options]['code'] = val
      end
      opts.on('--source VALUE', String, "Source Type. local, repository, url. Only applies to script task types.") do |val|
        file_params['sourceType'] = val
      end
      opts.on('--content TEXT', String, "Contents of the task script. This implies source is local.") do |val|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        file_params['content'] = val
      end
      opts.on('--file FILE', "File containing the task script. This can be used instead of --content" ) do |filename|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          file_params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on('--url VALUE', String, "URL, for use when source is url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-path VALUE', String, "Content Path, for use when source is repository or url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-ref VALUE', String, "Content Ref (Version Ref), for use when source is repository") do |val|
        file_params['contentRef'] = val
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
      opts.on('--allow-custom-config [on|off]', String, "Allow Custom Config") do |val|
        options[:options]['allowCustomConfig'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    task_name = args[0]
    connect(options)
    begin
      task = find_task_by_name_or_id(task_name)
      return 1 if task.nil?
      task_type = find_task_type_by_name(task['taskType']['name'])
      return 1 if task_type.nil?
      
      # file content param varies, heh
      has_file_content = false
      task_option_types = task_type['optionTypes'] || []
      task_option_types.each do |it|
        if it['type'] == 'file-content'
          has_file_content = true
        end
      end
      # inject file_params into options for file-content prompt
      # or into taskOptions.script for types not yet using file-content
      unless file_params.empty?
        if has_file_content
          options[:options]['file'] ||= {}
          options[:options]['file'].merge!(file_params)
        else
          options[:options]['taskOptions'] ||= {}
          options[:options]['taskOptions']['script'] = file_params['content'] if file_params['content']
        end
      end

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'task' => passed_options})  unless passed_options.empty?
        # payload.deep_merge!({'task' => {'file' => file_params}}) unless file_params.empty?
      else
        # construct payload
        payload = {}
        payload.deep_merge!({'task' => passed_options})  unless passed_options.empty?
        # payload.deep_merge!({'task' => {'file' => file_params}}) unless file_params.empty?

        if payload['task'].empty?
          print_red_alert "Specify at least one option to update"
          puts optparse
          return 1
        end

      end

      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.update(task['id'], payload)
        return 0
      end
      response = @tasks_interface.update(task['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        if !response['success']
          return 1
        end
      else
        print_green_success "Task #{response['task']['name']} updated"
        get([task['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
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

  def execute(args)
    params = {}
    options = {}
    target_type = nil
    instance_ids = []
    instances = []
    server_ids = []
    servers = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[task] --instance [instance] [options]")
      opts.on('--instance INSTANCE', String, "Instance name or id to execute the task on. This option can be passed more than once.") do |val|
        target_type = 'instance'
        instance_ids << val
      end
      opts.on('--instances [LIST]', Array, "Instances, comma separated list of instance names or IDs.") do |list|
        target_type = 'instance'
        instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--host HOST', String, "Host name or id to execute the task on. This option can be passed more than once.") do |val|
        target_type = 'server'
        server_ids << val
      end
      opts.on('--hosts [LIST]', Array, "Hosts, comma separated list of host names or IDs.") do |list|
        target_type = 'server'
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--server HOST', String, "alias for --host") do |val|
        target_type = 'server'
        server_ids << val
      end
      opts.on('--servers [LIST]', Array, "alias for --hosts") do |list|
        target_type = 'server'
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.add_hidden_option('--server')
      opts.add_hidden_option('--servers')
      opts.on('-a', '--appliance', "Execute on the appliance, the target is the appliance itself.") do
        target_type = 'appliance'
      end
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    task_name = args[0]
    connect(options)
    begin
      task = find_task_by_name_or_id(task_name)
      return 1 if task.nil?

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'job' => passed_options})  unless passed_options.empty?
      else
        if instance_ids.size > 0 && server_ids.size > 0
          raise_command_error "Pass --instance or --host, not both.\n#{optparse}"
        elsif instance_ids.size > 0
          instance_ids.each do |instance_id|
            instance = find_instance_by_name_or_id(instance_id)
            return 1 if instance.nil?
            instances << instance
          end
          params['instances'] = instances.collect {|it| it['id'] }
        elsif server_ids.size > 0
          server_ids.each do |server_id|
            server = find_server_by_name_or_id(server_id)
            return 1 if server.nil?
            servers << server
          end
          params['servers'] = servers.collect {|it| it['id'] }
        elsif target_type == 'appliance'
          # cool, run it locally.
        else
          raise_command_error "missing required option: --instance or --host\n#{optparse}"
        end

        # todo: prompt to task optionTypes for customOptions
        if task['optionTypes']
          
        end

        params['targetType'] = target_type

        job_payload = {}
        job_payload.deep_merge!(params)
        job_payload.deep_merge!(passed_options) unless passed_options.empty?
        payload = {'job' => job_payload}
      end

      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.run(task['id'], payload)
        return
      end
      json_response = @tasks_interface.run(task['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return json_response['success'] ? 0 : 1
      else
        target_desc = ""
        if instances.size() > 0
          target_desc = (instances.size() == 1) ? "instance #{instances[0]['name']}" : "#{instances.size()} instances"
        elsif servers.size() > 0
          target_desc = (servers.size() == 1) ? "host #{servers[0]['name']}" : "#{servers.size()} hosts"
        elsif target_type == 'appliance'
          target_desc = "appliance"
        end
        print_green_success "Executing task #{task['name']} on #{target_desc}"
        # todo: refresh, use get processId and load process record isntead? err
        if json_response["jobExecution"] && json_response["jobExecution"]["id"]
          get_args = [json_response["jobExecution"]["id"], "--details"] + (options[:remote] ? ["-r",options[:remote]] : [])
          Morpheus::Logging::DarkPrinter.puts((['jobs', 'get-execution'] + get_args).join(' ')) if Morpheus::Logging.debug?
          return ::Morpheus::Cli::JobsCommand.new.handle(['get-execution'] + get_args)
        end
        return json_response['success'] ? 0 : 1
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_task_types(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List task types."
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @tasks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.list_types(params)
        return
      end
      json_response = @tasks_interface.list_types(params)


      render_result = render_with_format(json_response, options, 'taskTypes')
      return 0 if render_result
      
      title = "Morpheus Task Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      task_types = json_response['taskTypes']
      if task_types.empty?
        print cyan,"No task types found.",reset,"\n"
      else
        print cyan
        rows = task_types.collect do |task_type|
          {name: task_type['name'], id: task_type['id'], code: task_type['code'], description: task_type['description']}
        end
        print as_pretty_table(rows, [:id, :name, :code], options)
        #print_results_pagination(json_response)
        print_results_pagination({size:task_types.size,total:task_types.size})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_task_type(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a task type.\n" +
                    "[type] is required. This is the id or code or name of a task type."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      @tasks_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @tasks_interface.dry.get_type(args[0].to_i)
        else
          print_dry_run @tasks_interface.dry.list_types({name:args[0]})
        end
        return
      end
      # find_task_type_by_name actually finds by name or code id
      task_type = find_task_type_by_name(args[0])
      return 1 if task_type.nil?
      json_response = {'taskType' => task_type}  # skip redundant request
      # json_response = @tasks_interface.get(task_type['id'])
      
      render_result = render_with_format(json_response, options, 'taskType')
      return 0 if render_result

      task_type = json_response['taskType']

      title = "Morpheus Task Type"
      
      print_h1 "Morpheus Task Type", [], options
      
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'name',
        #"Description" => 'description',
        "Scriptable" => lambda {|it| format_boolean(it['scriptable']) },
        # lots more here
        # "enabled" => lambda {|it| format_boolean(it['enabled']) },
        # "hasResults" => lambda {|it| format_boolean(it['hasResults']) },
        # "allowRemoteKeyAuth" => lambda {|it| format_boolean(it['allowRemoteKeyAuth']) },
        # "allowExecuteLocal" => lambda {|it| format_boolean(it['allowExecuteLocal']) },
        # "allowExecuteRemote" => lambda {|it| format_boolean(it['allowExecuteRemote']) },
        # "allowExecuteResource" => lambda {|it| format_boolean(it['allowExecuteResource']) },
        # "allowLocalRepo" => lambda {|it| format_boolean(it['allowLocalRepo']) },
        # "allowRemoteKeyAuth" => lambda {|it| format_boolean(it['allowRemoteKeyAuth']) },
      }
      print_description_list(description_cols, task_type)

      option_types = task_type['optionTypes'] || []
      option_types = option_types.sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      if !option_types.empty?
        print_h2 "Config Option Types", [], options
        option_type_cols = {
          "Name" => lambda {|it| it['fieldContext'].to_s != '' ? "#{it['fieldContext']}.#{it['fieldName']}" : it['fieldName'] },
          "Label" => lambda {|it| it['fieldLabel'] },
          "Type" => lambda {|it| it['type'] },
        }
        print cyan
        print as_pretty_table(option_types, option_type_cols)
      end
      
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
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
        return nil
      else
        raise e
      end
    end
  end

  def find_task_by_name(name)
    tasks = @tasks_interface.list({name: name.to_s})['tasks']
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
    @all_task_types ||= @tasks_interface.list_types({max:1000})['taskTypes']

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
      {"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
      # {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(tasks, columns, opts)
  end

  def find_instance_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_instance_by_id(val)
    else
      return find_instance_by_name(val)
    end
  end

  def find_instance_by_id(id)
    begin
      json_response = @instances_interface.get(id.to_i)
      return json_response['instance']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_instance_by_name(name)
    instances = @instances_interface.list({name: name.to_s})['instances']
    if instances.empty?
      print_red_alert "Instance not found by name #{name}"
      return nil
    elsif instances.size > 1
      print_red_alert "#{instances.size} instances found by name #{name}"
      as_pretty_table(instances, [:id, :name], {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return instances[0]
    end
  end

  def find_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_server_by_id(val)
    else
      return find_server_by_name(val)
    end
  end

  def find_server_by_id(id)
    begin
      json_response = @servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Server not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_server_by_name(name)
    servers = @servers_interface.list({name: name.to_s})['servers']
    if servers.empty?
      print_red_alert "Host not found by name #{name}"
      return nil
    elsif servers.size > 1
      print_red_alert "#{servers.size} hosts found by name #{name}"
      as_pretty_table(servers, [:id, :name], {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return servers[0]
    end
  end

end
