# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Workflows
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove
  set_default_subcommand :list
  
  # def initialize()
  #   @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  # end

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
        print_dry_run @task_sets_interface.dry.get(params)
        return
      end
      json_response = @task_sets_interface.get(params)
      task_sets = json_response['taskSets']
      # print result and return output
      if options[:json]
        if options[:include_fields]
          json_response = {"taskSets" => filter_data(json_response["taskSets"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['taskSets'], options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"taskSets" => filter_data(json_response["taskSets"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
        return 0
      else
        task_sets = json_response['taskSets']
        title = "Morpheus Workflows"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if task_sets.empty?
          print cyan,"No workflows found.",reset,"\n"
        else
          print cyan
          print_workflows_table(task_sets)
          print_results_pagination(json_response)
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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] --tasks x,y,z")
      opts.on("--tasks x,y,z", Array, "List of tasks to run in order") do |list|
        options[:task_names] = list
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1 || options[:task_names].empty?
      puts optparse
      exit 1
    end
    workflow_name = args[0]
    connect(options)
    begin
      tasks = []
      options[:task_names].each do |task_name|
        tasks << find_task_by_name_or_id(task_name.to_s.strip)['id']
      end

      payload = {taskSet: {name: workflow_name, tasks: tasks}}
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.create(payload)
        return
      end
      json_response = @task_sets_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        workflow = json_response['taskSet']
        print "\n", cyan, "Workflow #{workflow['name']} created successfully", reset, "\n\n"
        get([workflow['id']])
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
    workflow_name = id
    begin
      if options[:dry_run]
        if workflow_name.to_s =~ /\A\d{1,}\Z/
          print_dry_run @task_sets_interface.dry.get(workflow_name.to_i)
        else
          print_dry_run @task_sets_interface.dry.get({name: workflow_name})
        end
        return
      end
      workflow = find_workflow_by_name_or_id(workflow_name)
      exit 1 if workflow.nil?
      # refetch it..
      json_response = {'taskSet' => workflow}
      unless workflow_name.to_s =~ /\A\d{1,}\Z/
        json_response = @task_sets_interface.get(workflow['id'])
      end
      workflow = json_response['taskSet']
      if options[:json]
        json_response = {"taskSet" => filter_data(json_response["taskSet"], options[:include_fields]) } if options[:include_fields]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        json_response = {"taskSet" => filter_data(json_response["taskSet"], options[:include_fields]) } if options[:include_fields]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['taskSet']], options)
        return 0
      else
        # tasks = []
        # (workflow['tasks'] || []).each do |task_name|
        #   tasks << find_task_by_name_or_id(task_name)['id']
        # end
        tasks = workflow['taskSetTasks'].sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }
        print_h1 "Workflow Details"

        print cyan
        description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }
        print_description_list(description_cols, workflow)

        #task_names = tasks.collect {|it| it['name'] }
        print_h2 "Workflow Tasks"
        if tasks.empty?
          print yellow,"No tasks in this workflow.",reset,"\n"
        else
          print cyan
          # tasks.each_with_index do |taskSetTask, index|
          #   puts "#{(index+1).to_s.rjust(3, ' ')}. #{taskSetTask['task']['name']}"
          # end
          task_set_task_columns = [
            # this is the ID needed for the config options, by name would be nicer
            {"ID" => lambda {|it| it['id'] } }, 
            {"TASK ID" => lambda {|it| it['task']['id'] } },
            {"NAME" => lambda {|it| it['task']['name'] } },
            {"TYPE" => lambda {|it| it['task']['taskType'] ? it['task']['taskType']['name'] : '' } },
            {"PHASE" => lambda {|it| it['taskPhase'] } }, # not returned yet?
          ]
          print cyan
          puts as_pretty_table(tasks, task_set_task_columns)
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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] --tasks x,y,z")
      opts.on("--tasks x,y,z", Array, "New list of tasks to run in order") do |list|
        options[:task_names]= list
      end
      opts.on("--name NAME", String, "New name for workflow") do |val|
        options[:new_name] = val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1 || (options[:new_name].empty? && options[:task_names].empty?)
      puts optparse
      exit 1
    end
    workflow_name = args[0]
    connect(options)
    begin
      workflow = find_workflow_by_name_or_id(workflow_name)
      payload = {taskSet: {id: workflow['id']} }
      tasks = []
      if options[:task_names]
        options[:task_names].each do |task_name|
          tasks << find_task_by_name_or_id(task_name)['id']
        end
        payload[:taskSet][:tasks] = tasks
      else
        payload[:taskSet][:tasks] = workflow['tasks']
      end
      if options[:new_name]
        payload[:taskSet][:name] = options[:new_name]
      end
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.update(workflow['id'], payload)
        return
      end
      json_response = @task_sets_interface.update(workflow['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print "\n", cyan, "Workflow #{json_response['taskSet']['name']} updated successfully", reset, "\n\n"
        get([workflow['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = "Usage: morpheus workflows remove [name]"
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    workflow_name = args[0]
    connect(options)
    begin
      workflow = find_workflow_by_name_or_id(workflow_name)
      exit 1 if workflow.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the workflow #{workflow['name']}?")
        exit 1
      end
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.destroy(workflow['id'])
        return
      end
      json_response = @task_sets_interface.destroy(workflow['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print "\n", cyan, "Workflow #{workflow['name']} removed", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private

  def find_workflow_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_workflow_by_id(val)
    else
      return find_workflow_by_name(val)
    end
  end

  def find_workflow_by_id(id)
    begin
      json_response = @task_sets_interface.get(id.to_i)
      return json_response['taskSet']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Workflow not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_workflow_by_name(name)
    workflows = @task_sets_interface.get({name: name.to_s})['taskSets']
    if workflows.empty?
      print_red_alert "Workflow not found by name #{name}"
      return nil
    elsif workflows.size > 1
      print_red_alert "#{workflows.size} workflows by name #{name}"
      print_workflows_table(workflows, {color: red})
      print reset,"\n\n"
      return nil
    else
      return workflows[0]
    end
  end

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

  def print_workflows_table(workflows, opts={})
    columns = [
      {"ID" => lambda {|workflow| workflow['id'] } },
      {"NAME" => lambda {|workflow| workflow['name'] } },
      {"TASKS" => lambda {|workflow| 
        (workflow['taskSetTasks'] || []).sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }.collect { |taskSetTask|
          taskSetTask['task']['name']
        }.join(', ')
       } },
      {"DATE CREATED" => lambda {|workflow| format_local_dt(workflow['dateCreated']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(workflows, columns, opts)
  end
end
