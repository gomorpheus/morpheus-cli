# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Workflows
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove

  # def initialize() 
  # 	@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
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
        print_dry_run @task_sets_interface.dry.get(params)
        return
      end
      json_response = @task_sets_interface.get(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        task_sets = json_response['taskSets']
        print "\n" ,cyan, bold, "Morpheus Workflows\n","==================", reset, "\n\n"
        if task_sets.empty?
          puts yellow,"No workflows currently configured.",reset
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
      build_common_options(opts, options, [:json, :dry_run, :remote])
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
        print "\n", cyan, "Workflow #{json_response['taskSet']['name']} created successfully", reset, "\n\n"
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
    workflow_name = args[0]
    connect(options)
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
      json_response = @task_sets_interface.get(workflow['id'])
      workflow = json_response['taskSet']

      if options[:json]
        #puts JSON.pretty_generate(workflow)
        puts JSON.pretty_generate(json_response)
        print "\n"
      else
        # tasks = []
        # (workflow['tasks'] || []).each do |task_name|
        # 	tasks << find_task_by_name_or_id(task_name)['id']
        # end
        tasks = workflow['taskSetTasks'].sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }
        print "\n" ,cyan, bold, "Workflow Details\n","==================", reset, "\n\n"
        print cyan
        puts "ID: #{workflow['id']}"
        puts "Name: #{workflow['name']}"
        #puts "Description: #{workflow['description']}"
        #task_names = tasks.collect {|it| it['name'] }
        print "\n", cyan, "Tasks:\n"
        tasks.each_with_index do |taskSetTask, index|
          puts "#{(index+1).to_s.rjust(3, ' ')}. #{taskSetTask['task']['name']}" 
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
    table_color = opts[:color] || cyan
    rows = workflows.collect do |workflow|
      task_names = []
      workflow['taskSetTasks'].sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }.each do |taskSetTask|
        task_names << taskSetTask['task']['name']
      end
      {
        id: workflow['id'], 
        name: workflow['name'], 
        tasks: task_names.join(', '), 
        dateCreated: format_local_dt(workflow['dateCreated']) 
      }
    end
        print table_color
    tp rows, [
      :id, 
      :name, 
      :tasks
    ]
    print reset
  end

end
