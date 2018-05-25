# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
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
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.get(params)
        return
      end
      json_response = @tasks_interface.get(params)
      # print result and return output
      if options[:json]
        if options[:include_fields]
          json_response = {"tasks" => filter_data(json_response["tasks"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['tasks'], options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"tasks" => filter_data(json_response["tasks"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
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
        json_response = {"task" => filter_data(json_response["task"], options[:include_fields]) } if options[:include_fields]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        json_response = {"task" => filter_data(json_response["task"], options[:include_fields]) } if options[:include_fields]
        puts as_yaml(json_response, options)
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
          "Type" => lambda {|it| it['taskType']['name'] },
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
    optparse = OptionParser.new do|opts|
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
        print "\n", cyan, "Task #{response['task']['name']} updated", reset, "\n\n"
        get([task['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def task_types(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
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
          tasks_table_data = task_types.collect do |task_type|
            {name: task_type['name'], id: task_type['id'], code: task_type['code'], description: task_type['description']}
          end
          tp tasks_table_data, :id, :name, :code
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
    options = {}
    task_name = nil
    task_type_name = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] -t TASK_TYPE")
      opts.on( '-t', '--type TASK_TYPE', "Task Type" ) do |val|
        task_type_name = val
      end
      opts.on('--name NAME', String, "Task Name" ) do |val|
        task_name = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --O taskOptions.script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          options[:options] ||= {}
          options[:options]['taskOptions'] ||= {}
          options[:options]['taskOptions']['script'] = File.read(full_filename)
          # params['script'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
        # use the filename as the name by default.
        if !params['name']
          options[:options] ||= {}
          options[:options]['taskOptions'] ||= {}
          options[:options]['taskOptions']['script'] = File.read(full_filename)
          params['name'] = File.basename(full_filename)
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args[0]
      task_name = args[0]
    end

    if task_name.nil? || task_type_name.nil?
      puts optparse
      exit 1
    end
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # construct payload
        task_type = find_task_type_by_name(task_type_name)
        if task_type.nil?
          puts "Task Type not found by id '#{task_type_name}'!"
          return 1
        end
        input_options = Morpheus::Cli::OptionTypes.prompt(task_type['optionTypes'],options[:options],@api_client, options[:params])
        payload = {task: {name: task_name, taskOptions: input_options['taskOptions'], taskType: {code: task_type['code'], id: task_type['id']}}}
      end
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
        print "\n", cyan, "Task #{task['name']} created successfully", reset, "\n\n"
        get([task['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    task_name = args[0]
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[task]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
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
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.destroy(task['id'])
        return
      end
      json_response = @tasks_interface.destroy(task['id'])
      if options[:json]
        print JSON.pretty_generate(json_response),"\n"
      elsif !options[:quiet]
        print "\n", cyan, "Task #{task['name']} removed", reset, "\n\n"
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
    results = @tasks_interface.task_types(val)
    result = nil
    if !results['taskTypes'].nil? && !results['taskTypes'].empty?
      result = results['taskTypes'][0]
    elsif val.to_i.to_s == val
      results = @tasks_interface.task_types(val.to_i)
      result = results['taskType']
    end
    if result.nil?
      print_red_alert "Task Type not found by '#{val}'"
      return nil
    end
    return result
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
