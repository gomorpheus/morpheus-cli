require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/option_types'

class Morpheus::Cli::Instances
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  register_subcommands :list, :get, :add, :update, :remove, :logs, :stats, :stop, :start, :restart, :suspend, :eject, :backup, :backups, :stop_service, :start_service, :restart_service, :resize, :clone, :envs, :setenv, :delenv, :security_groups, :apply_security_groups, :firewall_enable, :firewall_disable, :run_workflow, :import_snapshot, :console, :status_check
  alias_subcommand :details, :get
  set_default_subcommand :list
  
  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @instances_interface = @api_client.instances
    @task_sets_interface = @api_client.task_sets
    @logs_interface = @api_client.logs
    @tasks_interface = @api_client.tasks
    @instance_types_interface = @api_client.instance_types
    @clouds_interface = @api_client.clouds
    @provision_types_interface = @api_client.provision_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_group
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def add(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[type] [name]")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--type CODE', "Instance Type" ) do |val|
        options[:instance_type_code] = val
      end
      opts.on("--copies NUMBER", Integer, "Number of copies to provision") do |val|
        options[:copies] = val.to_i
      end
      opts.on("--layout-size NUMBER", Integer, "Apply a multiply factor of containers/vms within the instance") do |val|
        options[:layout_size] = val.to_i
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end

    optparse.parse!(args)
    connect(options)

    # support old format of `instance add TYPE NAME`
    if args[0]
      options[:instance_type_code] = args[0]
    end
    if args[1]
      options[:instance_name] = args[1]
    end
    # use active group by default
    options[:group] ||= @active_group_id

    options[:name_required] = true
    begin

      payload = prompt_new_instance(options)
      payload[:copies] = options[:copies] if options[:copies] && options[:copies] > 0
      payload[:layoutSize] = options[:layout_size] if options[:layout_size] && options[:layout_size] > 0
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create(payload)
        return
      end
      json_response = @instances_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        instance_name = json_response["instance"]["name"]
        print_green_success "Provisioning instance #{instance_name}"
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    usage = "Usage: morpheus instances update [name] [options]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])

      payload = {
        'instance' => {id: instance["id"]}
      }

      update_instance_option_types = [
        {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this instance'},
        {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
        {'fieldName' => 'instanceContext', 'fieldLabel' => 'Environment', 'type' => 'select', 'required' => false, 'selectOptions' => instance_context_options()},
        {'fieldName' => 'tags', 'fieldLabel' => 'Tags', 'type' => 'text', 'required' => false}
      ]

      params = options[:options] || {}

      if params.empty?
        puts "\n#{usage}\n"
        option_lines = update_instance_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      instance_keys = ['name', 'description', 'instanceContext', 'tags']
      params = params.select {|k,v| instance_keys.include?(k) }
      params['tags'] = params['tags'].split(',').collect {|it| it.to_s.strip }.compact.uniq if params['tags']
      payload['instance'].merge!(params)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated instance #{instance['name']}"
        list([])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def status_check(args)
    out = ""
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet, :json, :remote]) # no :dry_run, just do it man
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    # todo: just return status or maybe check if instance['status'] == args[0]
    instance = find_instance_by_name_or_id(args[0])
    exit_code = 0
    if instance['status'].to_s.downcase != (args[1] || "running").to_s.downcase
      exit_code = 1
    end
    if options[:json]
      mock_json = {status: instance['status'], exit: exit_code}
      out << as_json(mock_json, options)
      out << "\n"
    elsif !options[:quiet]
      out << cyan
      out << "Status: #{format_instance_status(instance)}"
      out << reset
      out << "\n"
    end
    print out unless options[:quiet]
    exit exit_code #return exit_code
  end

  def stats(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    ids = args
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _stats(arg, options)
    end
  end

  def _stats(arg, options)
    begin
      instance = find_instance_by_name_or_id(arg)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get(instance['id'])
        return 0
      end
      json_response = @instances_interface.get(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"stats" => filter_data(json_response["stats"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
        return 0
      end
      instance = json_response['instance']
      stats = json_response['stats'] || {}
      title = "Instance Stats: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title
      puts cyan + "Status: ".rjust(12) + format_instance_status(instance).to_s
      puts cyan + "Nodes: ".rjust(12) + (instance['containers'] ? instance['containers'].count : '').to_s
      # print "\n"
      #print_h2 "Instance Usage"
      print_stats_usage(stats)
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def console(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-n', '--node NODE_ID', "Scope console to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      # build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/terminal/#{instance['id']}"
      container_ids = instance['containers']
      if options[:node_id] && container_ids.include?(options[:node_id])
        link += "?containerId=#{options[:node_id]}"
      end

      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{link}"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      build_common_options(opts, options, [:list, :json, :csv, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      container_ids = instance['containers']
      if options[:node_id] && container_ids.include?(options[:node_id])
        container_ids = [options[:node_id]]
      end
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      if options[:dry_run]
        print_dry_run @logs_interface.dry.server_logs([server['id']], params)
        return
      end
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(container_ids, params)
        return
      end
      logs = @logs_interface.container_logs(container_ids, params)
      output = ""
      if options[:json]
        output << as_json(logs, options)
      else
        title = "Instance Logs: #{instance['name']} (#{instance['instanceType'] ? instance['instanceType']['name'] : ''})"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        # todo: startMs, endMs, sorts insteaad of sort..etc
        print_h1 title, subtitles
        if logs['data'].empty?
          output << "#{cyan}No logs found.#{reset}\n"
        else
          logs['data'].reverse.each do |log_entry|
            log_level = ''
            case log_entry['level']
            when 'INFO'
              log_level = "#{blue}#{bold}INFO#{reset}"
            when 'DEBUG'
              log_level = "#{white}#{bold}DEBUG#{reset}"
            when 'WARN'
              log_level = "#{yellow}#{bold}WARN#{reset}"
            when 'ERROR'
              log_level = "#{red}#{bold}ERROR#{reset}"
            when 'FATAL'
              log_level = "#{red}#{bold}FATAL#{reset}"
            end
            output << "[#{log_entry['ts']}] #{log_level} - #{log_entry['message']}\n"
          end
        end
        print output, reset, "\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(arg, options)
    begin
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @instances_interface.dry.get(arg.to_i)
        else
          print_dry_run @instances_interface.dry.get({name:arg})
        end
        return
      end
      instance = find_instance_by_name_or_id(arg)
      json_response = @instances_interface.get(instance['id'])
      if options[:json]
        if options[:include_fields]
          json_response = {"instance" => filter_data(json_response["instance"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"instance" => filter_data(json_response["instance"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
        return 0
      end

      if options[:csv]
        puts records_as_csv([json_response['instance']], options)
        return 0
      end
      instance = json_response['instance']
      stats = json_response['stats'] || {}
      # load_balancers = stats = json_response['loadBalancers'] || {}

      print_h1 "Instance Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Type" => lambda {|it| it['instanceType']['name'] },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Environment" => 'instanceContext',
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].count : 0 },
        "Connection" => lambda {|it| format_instance_connection_string(it) },
        #"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Status" => lambda {|it| format_instance_status(it) }
      }
      print_description_list(description_cols, instance)

      if (stats)
        print_h2 "Instance Usage"
        print_stats_usage(stats)
      end
      print reset, "\n"

      #puts instance
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backups(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backups(instance['id'], params)
        return
      end
      json_response = @instances_interface.backups(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      backups = json_response['backups']
      stats = json_response['stats'] || {}
      # load_balancers = stats = json_response['loadBalancers'] || {}

      print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})"
      backup_rows = backups.collect {|it| {id: it['id'], name: it['name'], dateCreated: it['dateCreated']} }
      print cyan
      tp backup_rows, [
        :id,
        :name,
        {:dateCreated => {:display_name => "Date Created"} }
      ]
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def clone(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] -g GROUP")
      build_option_type_options(opts, options, clone_instance_option_types(false))
      opts.on( '-g', '--group GROUP', "Group Name or ID for the new instance" ) do |val|
        options[:group] = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    if !options[:group]
      print_red_alert "GROUP is required."
      puts optparse
      exit 1
    end
    connect(options)
    begin
      options[:options] ||= {}
      # use the -g GROUP or active group by default
      options[:options]['group'] ||= options[:group] # || @active_group_id # always choose a group for now?
      # support [new-name] 
      # if args[1]
      #   options[:options]['name'] = args[1]
      # end
      payload = {

      }
      params = Morpheus::Cli::OptionTypes.prompt(clone_instance_option_types, options[:options], @api_client, options[:params])
      group = find_group_by_name_or_id_for_provisioning(params.delete('group'))
      payload.merge!(params)
      payload['group'] = {id: group['id']}

      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to clone the instance '#{instance['name']}'?", options)
        exit 1
      end
      
      if options[:dry_run]
        print_dry_run @instances_interface.dry.clone(instance['id'], payload)
        return
      end
      json_response = @instances_interface.clone(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Cloning instance #{instance['name']} to '#{payload['name']}'"
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def envs(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get_envs(instance['id'])
        return
      end
      json_response = @instances_interface.get_envs(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      print_h1 "Instance Envs: #{instance['name']} (#{instance['instanceType']['name']})"
      print cyan
      envs = json_response['envs'] || {}
      if json_response['readOnlyEnvs']
        envs += json_response['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value'], :export => true}}
      end
      tp envs, :name, :value, :export
      print_h2 "Imported Envs"
      imported_envs = json_response['importedEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value']}}
      tp imported_envs
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def setenv(args)
    options = {}

    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] VAR VALUE [-e]")
      opts.on( '-e', "Exportable" ) do |exportable|
        options[:export] = exportable
      end
      opts.on( '-M', "Masked" ) do |masked|
        options[:masked] = masked
      end
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count < 3
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      evar = {name: args[1], value: args[2], export: options[:export], masked: options[:masked]}
      payload = {envs: [evar]}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create_env(instance['id'], payload)
        return
      end
      json_response = @instances_interface.create_env(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def delenv(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] VAR")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.del_env(instance['id'], args[1])
        return
      end
      json_response = @instances_interface.del_env(instance['id'], args[1])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop this instance?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.stop(instance['id'])
        return
      end
      json_response = @instances_interface.stop(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        print "\n"
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.start(instance['id'])
        return
      end
      json_response = @instances_interface.start(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart this instance?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.restart(instance['id'])
        return
      end
      json_response = @instances_interface.restart(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def suspend(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to suspend this instance?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.suspend(instance['id'])
        return
      end
      json_response = @instances_interface.suspend(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def eject(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("restart [name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to eject this instance?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.eject(instance['id'])
        return
      end
      json_response = @instances_interface.eject(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop_service(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop this instance?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.stop(instance['id'],false)
        return
      end
      json_response = @instances_interface.stop(instance['id'],false)
      if options[:json]
        puts as_json(json_response, options)
      else
        puts "Stopping service on #{args[0]}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start_service(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.start(instance['id'], false)
        return
      end
      json_response = @instances_interface.start(instance['id'],false)
      if options[:json]
        puts as_json(json_response, options)
      else
        puts "Starting service on #{args[0]}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart_service(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart this instance?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.restart(instance['id'],false)
        return
      end
      json_response = @instances_interface.restart(instance['id'],false)
      if options[:json]
        puts as_json(json_response, options)
      else
        puts "Restarting service on instance #{args[0]}"
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def resize(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])

      group_id = instance['group']['id']
      cloud_id = instance['cloud']['id']
      layout_id = instance['layout']['id']

      plan_id = instance['plan']['id']
      payload = {
        :instance => {:id => instance["id"]}
      }

      # avoid 500 error
      # payload[:servicePlanOptions] = {}

      puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"

      # prompt for service plan
      service_plans_json = @instances_interface.service_plans({zoneId: cloud_id, layoutId: layout_id})
      service_plans = service_plans_json["plans"]
      service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
      service_plans_dropdown.each do |plan|
        if plan['value'] && plan['value'].to_i == plan_id.to_i
          plan['name'] = "#{plan['name']} (current)"
        end
      end
      plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options])
      service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['servicePlan'].to_i }
      new_plan_id = service_plan["id"]
      #payload[:servicePlan] = new_plan_id # ew, this api uses servicePlanId instead
      #payload[:servicePlanId] = new_plan_id
      payload[:instance][:plan] = {id: service_plan["id"]}

      volumes_response = @instances_interface.volumes(instance['id'])
      current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

      # prompt for volumes
      volumes = prompt_resize_volumes(current_volumes, service_plan, options)
      if !volumes.empty?
        payload[:volumes] = volumes
      end

      # only amazon supports this option
      # for now, always do this
      payload[:deleteOriginalVolumes] = true

      if options[:dry_run]
        print_dry_run @instances_interface.dry.resize(instance['id'], payload)
        return
      end
      json_response = @instances_interface.resize(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        print_green_success "Resizing instance #{instance['name']}"
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backup(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to backup the instance '#{instance['name']}'?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backup(instance['id'])
        return
      end
      json_response = @instances_interface.backup(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        puts "Backup initiated."
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
      if group
        params['siteId'] = group['id']
      end

      # argh, this doesn't work because group_id is required for options/clouds
      # cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
      cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
      if cloud
        params['zoneId'] = cloud['id']
      end

      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @instances_interface.dry.list(params)
        return
      end
      json_response = @instances_interface.get(params)
      if options[:json]
        if options[:include_fields]
          json_response = {"instances" => filter_data(json_response["instances"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        if options[:include_fields]
          json_response = {"instances" => filter_data(json_response["instances"], options[:include_fields]) }
        end
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        # merge stats to be nice here..
        if json_response['instances']
          all_stats = json_response['stats'] || {}
          json_response['instances'].each do |it|
            it['stats'] ||= all_stats[it['id'].to_s] || all_stats[it['id']]
          end
        end
        puts records_as_csv(json_response['instances'], options)
      else
        instances = json_response['instances']

        title = "Morpheus Instances"
        subtitles = []
        if group
          subtitles << "Group: #{group['name']}".strip
        end
        if cloud
          subtitles << "Cloud: #{cloud['name']}".strip
        end
        if params[:phrase]
          subtitles << "Search: #{params[:phrase]}".strip
        end
        print_h1 title, subtitles
        if instances.empty?
          print yellow,"No instances found.",reset,"\n"
        else
          # print_instances_table(instances)
          # server returns stats in a separate key stats => {"id" => {} }
          # the id is a string right now..for some reason..
          all_stats = json_response['stats'] || {} 
          instances.each do |it|
            if !it['stats']
              found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
              it['stats'] = found_stats # || {}
            end
          end

          rows = instances.collect {|instance| 
            stats = instance['stats']
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            row = {
              id: instance['id'],
              name: instance['name'],
              connection: format_instance_connection_string(instance),
              environment: instance['instanceContext'],
              nodes: instance['containers'].count,
              status: format_instance_status(instance, cyan),
              type: instance['instanceType']['name'],
              group: !instance['group'].nil? ? instance['group']['name'] : nil,
              cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil,
              version: instance['instanceVersion'] ? instance['instanceVersion'] : '',
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan,
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, :name, :group, :cloud, :type, :version, :environment, :nodes, {:connection => {max_width: 20}}, :status, :cpu, :memory, :storage]
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {keepBackups: 'off', force: 'off'}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [-fB]")
      opts.on( '-f', '--force', "Force Remove" ) do
        query_params[:force] = 'on'
      end
      opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
        query_params[:keepBackups] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])

    end
    optparse.parse!(args)
    if args.count < 1
      puts "\n#{optparse}\n\n"
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the instance '#{instance['name']}'?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @instances_interface.dry.destroy(instance['id'],query_params)
        return
      end
      json_response = @instances_interface.destroy(instance['id'],query_params)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_disable(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_disable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_disable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_enable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_enable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @instances_interface.dry.security_groups(instance['id'])
        return
      end
      json_response = @instances_interface.security_groups(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for Instance: #{instance['name']}"
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      #print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
        print "\n"
      end
      print reset, "\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    security_group_ids = nil
    clear_or_secgroups_specified = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [-S] [-c]")
      opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        security_group_ids = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        security_group_ids = []
        clear_or_secgroups_specified = true
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    if !clear_or_secgroups_specified
      puts optparse
      exit
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      payload = {securityGroupIds: security_group_ids}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.apply_security_groups(instance['id'], payload)
        return
      end
      json_response = @instances_interface.apply_security_groups(instance['id'], payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      if !options[:quiet]
        security_groups([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def run_workflow(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [workflow] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts "\n#{optparse}\n\n"
      exit 1
    end
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    workflow = find_workflow_by_name(args[1])
    task_types = @tasks_interface.task_types()
    editable_options = []
    workflow['taskSetTasks'].sort{|a,b| a['taskOrder'] <=> b['taskOrder']}.each do |task_set_task|
      task_type_id = task_set_task['task']['taskType']['id']
      task_type = task_types['taskTypes'].find{ |current_task_type| current_task_type['id'] == task_type_id}
      task_opts = task_type['optionTypes'].select { |otype| otype['editable']}
      if !task_opts.nil? && !task_opts.empty?
        editable_options += task_opts.collect do |task_opt|
          new_task_opt = task_opt.clone
          new_task_opt['fieldContext'] = "#{task_set_task['id']}.#{new_task_opt['fieldContext']}"
        end
      end
    end
    params = options[:options] || {}

    if params.empty? && !editable_options.empty?
      puts optparse
      option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
      puts "\nAvailable Options:\n#{option_lines}\n\n"
      exit 1
    end

    workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
    begin
      if options[:dry_run]
        print_dry_run @instances_interface.dry.workflow(instance['id'],workflow['id'], workflow_payload)
        return
      end
      json_response = @instances_interface.workflow(instance['id'],workflow['id'], workflow_payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      else
        puts "Running workflow..."
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def import_snapshot(args)
    options = {}
    storage_provider_id = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on("--storage-provider ID", String, "Optional storage provider") do |val|
        storage_provider_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to import a snapshot of the instance '#{instance['name']}'?", options)
        exit 1
      end

      payload = {}

      # Prompt for Storage Provider, use default value.
      begin
        options[:options] ||= {}
        options[:options]['storageProviderId'] = storage_provider_id if storage_provider_id
        storage_provider_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.'}], options[:options], @api_client, {})
        if !storage_provider_prompt['storageProviderId'].empty?
          payload['storageProviderId'] = storage_provider_prompt['storageProviderId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load storage providers"
        #print_rest_exception(e, options)
        exit 1
      end

      if options[:dry_run]
        print_dry_run @instances_interface.dry.import_snapshot(instance['id'], payload)
        return
      end
      json_response = @instances_interface.import_snapshot(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        puts "Snapshot import initiated."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # check the instance
  def check_status
  end

  private
  def find_zone_by_name_or_id(group_id, val)
    zone = nil
    if val.to_s =~ /\A\d{1,}\Z/
      json_results = @clouds_interface.get(val.to_i)
      zone = json_results['zone']
      if zone.nil?
        print_red_alert "Cloud not found by id #{val}"
        exit 1
      end
    else
      json_results = @clouds_interface.get({groupId: group_id, name: val})
      zone = json_results['zones'] ? json_results['zones'][0] : nil
      if zone.nil?
        print_red_alert "Cloud not found by name #{val}"
        exit 1
      end
    end
    return zone
  end

  def find_workflow_by_name(name)
    task_set_results = @task_sets_interface.get(name)
    if !task_set_results['taskSets'].nil? && !task_set_results['taskSets'].empty?
      return task_set_results['taskSets'][0]
    else
      print_red_alert "Workflow not found by name #{name}"
      exit 1
    end
  end

  # def print_instances_table(instances, opts={})
  #   table_color = opts[:color] || cyan
  #   rows = instances.collect {|instance| 
  #     {
  #       id: instance['id'],
  #       name: instance['name'],
  #       connection: format_instance_connection_string(instance),
  #       environment: instance['instanceContext'],
  #       nodes: instance['containers'].count,
  #       status: format_instance_status(instance, table_color),
  #       type: instance['instanceType']['name'],
  #       group: !instance['group'].nil? ? instance['group']['name'] : nil,
  #       cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil
  #     }
  #   }
  #   print table_color
  #   tp rows, :id, :name, :group, :cloud, :type, :environment, :nodes, :connection, :status
  #   print reset
  # end

  def format_instance_status(instance, return_color=cyan)
    out = ""
    status_string = instance['status']
    if status_string == 'running'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'unknown'
      out << "#{white}#{status_string.upcase}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_instance_connection_string(instance)
    if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
      connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
    end
  end

  def clone_instance_option_types(connected=true)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for the new instance'},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => true},
    ]
  end
end
