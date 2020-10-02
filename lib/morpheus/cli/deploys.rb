require 'morpheus/cli/cli_command'
require 'yaml'

class Morpheus::Cli::Deploys
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::DeploymentsHelper
  
  set_command_name :deploys
  set_command_description "View and manage instance deploys."
  register_subcommands :list, :get, :add, :update, :remove, :deploy

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @instances_interface = @api_client.instances
    @deploy_interface = @api_client.deploy
    @deployments_interface = @api_client.deployments
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
      opts.footer = <<-EOT
List deploys.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @deploy_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.list(params)
      return
    end
    json_response = @deploy_interface.list(params)
    app_deploys = json_response[app_deploy_list_key]
    render_response(json_response, options, app_deploy_list_key) do
      print_h1 "Morpheus Deploys", parse_list_subtitles(options), options
      if app_deploys.empty?
        print cyan,"No deploys found.",reset,"\n"
      else
        print as_pretty_table(app_deploys, app_deploy_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if app_deploys.empty?
      return 1, "no deploys found"
    else
      return 0, nil
    end
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific instance deploy.
[id] is required. This is the name or id of a deployment.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @deploy_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.get(id, params)
      return 0
    end
    json_response = @deploy_interface.get(id, params)
    app_deploy = json_response[app_deploy_object_key]
    render_response(json_response, options, app_deploy_object_key) do
      print_h1 "Deploy Details", [], options
      print cyan
      print_description_list(app_deploy_column_definitions, app_deploy)
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [deployment] [version] [options]")
      build_option_type_options(opts, options, add_app_deploy_option_types)
      build_option_type_options(opts, options, add_app_deploy_advanced_option_types)
      opts.on(nil, "--stageOnly", "Stage Only, do not run the deployment right away.") do |val|
        params['stageOnly'] = true
      end
      opts.on("-c", "--config JSON", String, "Config for deployment") do |val|
        parse_result = parse_json_or_yaml(val)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new instance deploy.
The new deployment is deployed right away, unless --stage-only is
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:3)
    options[:options]['instance'] = args[0] if args[0]
    options[:options]['deployment'] = args[1] if args[1]
    options[:options]['version'] = args[2] if args[2]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({app_deploy_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({app_deploy_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_app_deploy_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_app_deploy_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload[app_deploy_object_key].deep_merge!(params)
    end
    @deploy_interface.setopts(options)
    instance_id = payload[app_deploy_object_key]['instance']
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.create(instance_id, payload)
      return 0, nil
    end
    # unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to deploy?")
    #   return 9, "aborted command"
    # end
    json_response = @deploy_interface.create(instance_id, payload)
    app_deploy = json_response[app_deploy_object_key]
    render_response(json_response, options, app_deploy_object_key) do
      if app_deploy['status'] == 'staged'
        begin
          print_green_success "Staged Deploy #{app_deploy['deployment']['name']} version #{app_deploy['deploymentVersion']['userVersion']} to instance #{app_deploy['instance']['name']}"
        rescue => ex
          print_green_success "Staged Deploy"
        end
      else
        begin
          print_green_success "Deploying #{app_deploy['deployment']['name']} version #{app_deploy['deploymentVersion']['userVersion']} to instance #{app_deploy['instance']['name']}"
        rescue => ex
          print_green_success "Deploying"
        end
      end
      return _get(app_deploy["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      opts.on("-c", "--config JSON", String, "Config for deployment") do |val|
        parse_result = parse_json_or_yaml(val)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      #build_option_type_options(opts, options, update_app_deploy_option_types)
      #build_option_type_options(opts, options, update_app_deploy_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an instance deploy.
[id] is required. This is the name or id of an instance deploy.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    app_deploy = find_app_deploy_by_id(args[0])
    return 1 if app_deploy.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({app_deploy_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({app_deploy_object_key => parse_passed_options(options)})
      # do not prompt on update
      #v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_app_deploy_option_types, options[:options], @api_client, options[:params])
      #v_prompt.deep_compact!
      #params.deep_merge!(v_prompt)
      #advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_app_deploy_advanced_option_types, options[:options], @api_client, options[:params])
      #advanced_config.deep_compact!
      #params.deep_merge!(advanced_config)
      payload.deep_merge!({app_deploy_object_key => params})
      if payload[app_deploy_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @deploy_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.update(app_deploy['id'], payload)
      return
    end
    json_response = @deploy_interface.update(app_deploy['id'], payload)
    app_deploy = json_response[app_deploy_object_key]
    render_response(json_response, options, app_deploy_object_key) do
      print_green_success "Deploying..."
      return _get(app_deploy["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an instance deploy.
[id] is required. This is the name or id of a deploy.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    app_deploy = find_app_deploy_by_id(args[0])
    return 1 if app_deploy.nil?
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the deploy #{app_deploy['id']}?")
      return 9, "aborted command"
    end
    @deploy_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.destroy(app_deploy['id'], params)
      return
    end
    json_response = @deploy_interface.destroy(app_deploy['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed deploy #{app_deploy['id']}"
    end
    return 0, nil
  end

  def deploy(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      opts.on("-c", "--config JSON", String, "Config for deployment") do |val|
        parse_result = parse_json_or_yaml(val)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      #build_option_type_options(opts, options, update_app_deploy_option_types)
      #build_option_type_options(opts, options, update_app_deploy_advanced_option_types)
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Deploy an instance deploy.
[id] is required. This is the name or id of an instance deploy.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    app_deploy = find_app_deploy_by_id(args[0])
    return 1 if app_deploy.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({app_deploy_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({app_deploy_object_key => parse_passed_options(options)})
      # do not prompt on update
      #v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_app_deploy_option_types, options[:options], @api_client, options[:params])
      #v_prompt.deep_compact!
      #params.deep_merge!(v_prompt)
      #advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_app_deploy_advanced_option_types, options[:options], @api_client, options[:params])
      #advanced_config.deep_compact!
      #params.deep_merge!(advanced_config)
      payload.deep_merge!({app_deploy_object_key => params})
      # if payload[app_deploy_object_key].empty? # || options[:no_prompt]
      #   raise_command_error "Specify at least one option to update.\n#{optparse}"
      # end
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to deploy #{app_deploy['deployment']['name']} version #{app_deploy['deploymentVersion']['userVersion']} to instance #{app_deploy['instance']['name']}?")
      return 9, "aborted command"
    end
    @deploy_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.update(app_deploy['id'], payload)
      return
    end
    json_response = @deploy_interface.deploy(app_deploy['id'], payload)
    app_deploy = json_response[app_deploy_object_key]
    render_response(json_response, options, app_deploy_object_key) do
      print_green_success "Deploying..."
      return _get(app_deploy["id"], {}, options)
    end
    return 0, nil
  end

  private

   ## Deploys (AppDeploy)

  def app_deploy_object_key
    'appDeploy'
  end

  def app_deploy_list_key
    'appDeploys'
  end

  def find_app_deploy_by_id(id)
    begin
      json_response = @deploy_interface.get(id.to_i)
      return json_response[app_deploy_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Deploy not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def app_deploy_column_definitions
    {
      "ID" => 'id',
      "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : it['instanceId'] },
      "Deployment" => lambda {|it| it['deployment']['name'] rescue '' },
      "Version" => lambda {|it| (it['deploymentVersion']['userVersion'] || it['deploymentVersion']['version']) rescue '' },
      # "Version ID" => lambda {|it| (it['deploymentVersion']['id']) rescue '' },
      "Deploy Date" => lambda {|it| format_local_dt(it['deployDate']) },
      "Status" => lambda {|it| format_app_deploy_status(it['status']) },
    }
  end

  def add_app_deploy_option_types
    [
      {'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params|
        @instances_interface.list({max:10000}.merge(api_params))['instances'].collect {|it|
          {'name' => it['name'], 'value' => it['id'], 'id' => it['id']}
        }
      }, 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'deployment', 'fieldLabel' => 'Deployment', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params|
        @deployments_interface.list({max:10000})['deployments'].collect {|it|
          {'name' => it['name'], 'value' => it['id'], 'id' => it['id']}
        }
      }, 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'version', 'fieldLabel' => 'Version', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params|
        @deployments_interface.list_versions(api_params['deployment'], {max:10000})['versions'].collect {|it|
          {'name' => (it['userVersion'] || it['version']), 'value' => it['id'], 'id' => it['id']}
        }
      }, 'required' => true, 'displayOrder' => 3}
    ]
  end

  def add_app_deploy_advanced_option_types
    [{'fieldName' => 'stageOnly', 'fieldLabel' => 'Stage Only', 'type' => 'checkbox', 'description' => 'If set to true the deploy will only be staged and not actually run', 'displayOrder' => 10}]
  end

  def update_app_deploy_option_types
    add_app_deploy_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def update_app_deploy_advanced_option_types
    add_app_deploy_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

end

