# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Tasks
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :'task-types'
  alias_subcommand :details, :get
  alias_subcommand :types, :'task-types'
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
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.get(params)
        return
      end
      json_response = @tasks_interface.get(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        tasks = json_response['tasks']
        print "\n" ,cyan, bold, "Morpheus Tasks\n","==================", reset, "\n\n"
        if tasks.empty?
          puts yellow,"No tasks currently configured.",reset
        else
          print cyan
          tasks_table_data = tasks.collect do |task|
            {name: task['name'], id: task['id'], type: task['taskType']['name']}
          end
          tp tasks_table_data, :id, :name, :type
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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[task]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    task_name = args[0]
    connect(options)
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
      task_type = find_task_type_by_name(task['taskType']['name'])
      if options[:json]
        puts JSON.pretty_generate({task:task})
        print "\n"
      else
        #print "\n", cyan, "Task #{task['name']} - #{task['taskType']['name']}\n\n"
        print "\n" ,cyan, bold, "Task Details\n","==================", reset, "\n\n"
        print cyan
        puts "ID: #{task['id']}"
        puts "Name: #{task['name']}"
        puts "Type: #{task['taskType']['name']}"
        #puts "Description: #{workflow['description']}"
        # print "\n", cyan, "Config:\n"
        task_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
          if optionType['fieldLabel'].to_s.downcase == 'script'
            print cyan,bold,"Script:","\n",reset,bright_black,"#{task['taskOptions'][optionType['fieldName']]}","\n",reset
          else
            print cyan,("#{optionType['fieldLabel']} : " + (optionType['type'] == 'password' ? "#{task['taskOptions'][optionType['fieldName']] ? '************' : ''}" : "#{task['taskOptions'][optionType['fieldName']] || optionType['defaultValue']}")),"\n"
          end
        end
        print reset,"\n"
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
        print JSON.pretty_generate(json_response)
      else
        task_types = json_response['taskTypes']
        print "\n" ,cyan, bold, "Morpheus Task Types\n","==================", reset, "\n\n"
        if task_types.nil? || task_types.empty?
          puts yellow,"No task types currently exist on this appliance. This could be a seed issue.",reset
        else
          print cyan
          tasks_table_data = task_types.collect do |task_type|
            {name: task_type['name'], id: task_type['id'], code: task_type['code'], description: task_type['description']}
          end
          tp tasks_table_data, :id, :name, :code, :description
        end

        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    task_type_name = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] -t TASK_TYPE")
      opts.on( '-t', '--type TASK_TYPE', "Task Type" ) do |val|
        task_type_name = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    task_name = args[0]
    if args.count < 1 || task_type_name.nil?
      puts optparse
      exit 1
    end
    connect(options)
    begin
      task_type = find_task_type_by_name(task_type_name)
      if task_type.nil?
        puts "Task Type not found!"
        exit 1
      end
      input_options = Morpheus::Cli::OptionTypes.prompt(task_type['optionTypes'],options[:options],@api_client, options[:params])
      payload = {task: {name: task_name, taskOptions: input_options['taskOptions'], taskType: {code: task_type['code'], id: task_type['id']}}}
      if options[:dry_run]
        print_dry_run @tasks_interface.dry.create(payload)
        return
      end
      json_response = @tasks_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print "\n", cyan, "Task #{json_response['task']['name']} created successfully", reset, "\n\n"
        list([])
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
        print JSON.pretty_generate(json_response)
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
end
