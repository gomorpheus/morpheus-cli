require 'morpheus/cli/cli_command'

class Morpheus::Cli::Deployments
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::DeploymentsHelper

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :list_versions, :get_version, :add_version, :update_version, :remove_version
  alias_subcommand :versions, :'list-versions'

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
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
      opts.footer = "List deployments."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.list(params)
      return
    end
    json_response = @deployments_interface.list(params)
    deployments = json_response['deployments']
    render_response(json_response, options, 'deployments') do
      print_h1 "Morpheus Deployments", parse_list_subtitles(options), options
      if deployments.empty?
        print cyan,"No deployments found.",reset,"\n"
      else
        print as_pretty_table(deployments, deployment_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if deployments.empty?
      return 1, "no deployments found"
    else
      return 0, nil
    end
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific deployment.
[deployment] is required. This is the name or id of a deployment.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    # lookup IDs if names are given
    id_list = id_list.collect do |id|
      if id.to_s =~ /\A\d{1,}\Z/
        id
      else
        deployment = find_deployment_by_name(id)
        if deployment
          deployment['id']
        else
          raise_command_error "deployment not found for name '#{id}'"
        end
      end
    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.get(id, params)
      print_dry_run @deployments_interface.dry.list_versions(id, {})
      return
    end
    json_response = @deployments_interface.get(id, params)
    deployment_versions = @deployments_interface.list_versions(id)['versions']
    deployment = json_response['deployment']
    render_response(json_response, options, 'deployment') do
      print_h1 "Deployment Details", [], options
      print cyan
      print_description_list(deployment_column_definitions, deployment)
      print_h2 "Versions", options
      if deployment_versions.empty?
        print cyan,"No versions found.",reset,"\n"
      else
        print as_pretty_table(deployment_versions, deployment_version_column_definitions.upcase_keys!, options)
        print_results_pagination({'size' => deployment_versions.size(), 'total' => deployment['versionCount']}, {:label => "version", :n_label => "versions"})
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def list_versions(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [search]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List versions of a specific deployment.
[deployment] is required. This is the name or id of a deployment.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1,max:2)
    deployment_name  = args[0]
    if args.count > 1
      options[:phrase] = args[1]
    end
    connect(options)
    params.merge!(parse_list_options(options))
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.list(params)
      return
    end
    deployment = find_deployment_by_name_or_id(deployment_name)
    exit 1 if deployment.nil?
    json_response = @deployments_interface.list_versions(deployment['id'], params)
    deployment_versions = json_response['versions']
    render_response(json_response, options, 'versions') do
      print_h1 "Deployment Versions", ["#{deployment['name']}"] + parse_list_subtitles(options), options
      if deployment_versions.empty?
        print cyan,"No versions found.",reset,"\n"
      else
        print as_pretty_table(deployment_versions, deployment_version_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if deployment_versions.empty?
      return 1, "no versions found"
    else
      return 0, nil
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_deployment_option_types)
      build_option_type_options(opts, options, add_deployment_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new deployment.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'deployment' => parse_passed_options(options)})
    else
      payload.deep_merge!({'deployment' => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_deployment_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_deployment_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload['deployment'].deep_merge!(params)
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @deployments_interface.create(payload)
    deployment = json_response['deployment']
    render_response(json_response, options, 'deployment') do
      print_green_success "Added deployment #{deployment['name']}"
      return _get(deployment["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [options]")
      build_option_type_options(opts, options, update_deployment_option_types)
      build_option_type_options(opts, options, update_deployment_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a deployment.
[deployment] is required. This is the name or id of a deployment.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    deployment = find_deployment_by_name_or_id(args[0])
    return 1 if deployment.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'deployment' => parse_passed_options(options)})
    else
      payload.deep_merge!({'deployment' => parse_passed_options(options)})
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_deployment_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_deployment_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload.deep_merge!({'deployment' => params})
      if payload['deployment'].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.update(deployment['id'], payload)
      return
    end
    json_response = @deployments_interface.update(deployment['id'], payload)
    deployment = json_response['deployment']
    render_response(json_response, options, 'deployment') do
      print_green_success "Updated deployment #{deployment['name']}"
      return _get(deployment["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a deployment.
[deployment] is required. This is the name or id of a deployment.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    deployment = find_deployment_by_name_or_id(args[0])
    return 1 if deployment.nil?
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.destroy(deployment['id'], params)
      return
    end
    json_response = @deployments_interface.destroy(deployment['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed deployment #{deployment['name']}"
    end
    return 0, nil
  end

  def get_version(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [options]")
      build_option_type_options(opts, options, add_deployment_version_option_types)
      build_option_type_options(opts, options, add_deployment_version_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new deployment version.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the deployment version identifier
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)

    deployment = find_deployment_by_name_or_id(args[0])
    return 1 if deployment.nil?
    id = args[1]
    if id.to_s =~ /\A\d{1,}\Z/
      id = id.to_i
    else
      deployment_version = find_deployment_version_by_name(deployment['id'], id)
      if deployment_version
        id = deployment_version['id']
      else
        # raise_command_error "deployment not found for name '#{id}'"
        return 1, "deployment version not found for name '#{id}'"
      end
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.get_version(deployment['id'], id, params)
      return
    end
    json_response = @deployments_interface.get_version(deployment['id'], id, params)
    deployment_version = json_response['version']
    render_response(json_response, options, 'version') do
      # print_h1 "Deployment Version Details", [deployment['name']], options
      print_h1 "Deployment Version Details", [], options
      print cyan
      #columns = deployment_version_column_definitions
      columns = {
        "ID" => 'id',
        "Deployment" => lambda {|it| deployment['name'] },
        "Version" => 'userVersion',
        "Deploy Type" => lambda {|it| it['deployType'] },
        "URL" => lambda {|it| 
          if it['deployType'] == 'fetch'
            "#{it['fetchUrl']}"
          elsif it['deployType'] == 'git'
            "#{it['gitUrl']}"
          end
        },
        "Ref" => lambda {|it| 
          if it['deployType'] == 'git'
            "#{it['gitRef']}"
          end
        },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      if deployment_version['deployType'] == 'git'
        columns['Git URL'] = columns['URL']
      elsif deployment_version['deployType'] == 'fetch'
        columns['Fetch URL'] = columns['URL']
        columns.delete('Ref')
      else
        columns.delete('URL')
        columns.delete('Ref')
      end
      print_description_list(columns, deployment_version)
      print reset,"\n"
    end
    return 0, nil
  end

  def add_version(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [options]")
      build_option_type_options(opts, options, add_deployment_version_option_types)
      build_option_type_options(opts, options, add_deployment_version_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new deployment version.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the deployment version identifier
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:2)
    connect(options)
    deployment = nil
    if args[0]
      deployment = find_deployment_by_name_or_id(args[0])
      return 1 if deployment.nil?
    else
      deployment_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deploymentId', 'fieldLabel' => 'Deployment', 'type' => 'select', 'required' => true, 'description' => 'Deployment to add version to', 'optionSource' => lambda { |api_client, api_params|
        @deployments_interface.list(max:10000)['deployments'].collect {|it|
          {'name' => it['name'], 'value' => it['id']}
        }
      }}], options[:options])['deploymentId']
      deployment = {'id' => deployment_id.to_i}
    end
    options[:options]['userVersion'] = args[1] if args[1]
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'version' => parse_passed_options(options)})
    else
      payload.deep_merge!({'version' => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_deployment_version_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_deployment_version_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload['version'].deep_merge!(params)
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.create_version(deployment['id'], payload)
      return 0, nil
    end
    json_response = @deployments_interface.create_version(deployment['id'], payload)
    deployment_version = json_response['version']
    render_response(json_response, options, 'version') do
      print_green_success "Added deployment version #{deployment_version['userVersion']}"
      return get_version([deployment["id"], deployment_version['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
  end

  def update_version(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [options]")
      build_option_type_options(opts, options, update_deployment_version_option_types)
      build_option_type_options(opts, options, update_deployment_version_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a deployment version.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the deployment version identifier
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:2)
    connect(options)
    deployment = find_deployment_by_name_or_id(args[0])
    return 1 if deployment.nil?
    deployment_version = find_deployment_version_by_name_or_id(deployment['id'], args[1])
    return 1 if deployment_version.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'version' => parse_passed_options(options)})
    else
      payload.deep_merge!({'version' => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_deployment_version_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_deployment_version_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload['version'].deep_merge!(params)
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.update_version(deployment['id'], deployment_version['id'], payload)
      return 0, nil
    end
    json_response = @deployments_interface.update_version(deployment['id'], deployment_version['id'], payload)
    deployment_version = json_response['version']
    render_response(json_response, options, 'version') do
      print_green_success "Updated deployment version #{deployment_version['userVersion']}"
      return get_version([deployment["id"], deployment_version['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
  end

  def remove_version(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a deployment version.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the version identifier of a deployment version.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    deployment = find_deployment_by_name_or_id(args[0])
    return 1 if deployment.nil?
    id = args[1]

    if id.to_s =~ /\A\d{1,}\Z/
      id = id.to_i
    else
      deployment_version = find_deployment_version_by_name(deployment['id'], id)
      if deployment_version
        id = deployment_version['id']
      else
        # raise_command_error "deployment not found for '#{id}'"
        return 1, "deployment version not found for '#{id}'"
      end
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.destroy(deployment['id'], params)
      return
    end
    json_response = @deployments_interface.destroy(deployment['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed deployment version #{deployment_version['userVersion']}"
    end
    return 0, nil
  end

  private

  def deployment_column_definitions
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Versions" => lambda {|it| it['versionCount'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  # this is not so simple, need to first choose select instance, host or provider
  def add_deployment_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 1}
    ]
  end

  def add_deployment_advanced_option_types
    []
  end

  def update_deployment_option_types
    add_deployment_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def update_deployment_advanced_option_types
    add_deployment_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  ## Deployment Versions

  def deployment_version_column_definitions
    {
      "ID" => 'id',
      "Version" => 'userVersion',
      "Deploy Type" => lambda {|it| it['deployType'] },
      "URL" => lambda {|it| 
        if it['deployType'] == 'fetch'
          "#{it['fetchUrl']}"
        elsif it['deployType'] == 'git'
          "#{it['gitUrl']}"
        end
      },
      "Ref" => lambda {|it| 
        if it['deployType'] == 'git'
          "#{it['gitRef']}"
        end
      },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  # this is not so simple, need to first choose select instance, host or provider
  def add_deployment_version_option_types
    [
      {'fieldName' => 'userVersion', 'fieldLabel' => 'Version', 'type' => 'text', 'required' => true, 'displayOrder' => 1, 'description' => 'This is the deployment version identifier (userVersion)'},
      {'fieldName' => 'deployType', 'fieldLabel' => 'Deploy Type', 'type' => 'select', 'optionSource' => 'deployTypes', 'required' => true, 'displayOrder' => 1, 'description' => 'This is the deployment version identifier (userVersion)', 'defaultValue' => 'file', 'code' => 'deployment.deployType'},
      {'fieldName' => 'fetchUrl', 'fieldLabel' => 'Fetch URL', 'type' => 'select', 'optionSource' => 'deployTypes', 'required' => true, 'displayOrder' => 1, 'description' => 'The URL to fetch the deployment file(s) from.', 'dependsOnCode' => 'deployment.deployType:fetch'},
      {'fieldName' => 'gitUrl', 'fieldLabel' => 'Git URL', 'type' => 'string', 'required' => true, 'displayOrder' => 1, 'description' => 'The URL to fetch the deployment file(s) from.', 'dependsOnCode' => 'deployment.deployType:git'},
      {'fieldName' => 'gitRef', 'fieldLabel' => 'Git Ref', 'type' => 'string', 'displayOrder' => 1, 'description' => 'The Git Reference to use, this the branch or tag name, defaults to master.', 'dependsOnCode' => 'deployment.deployType:git'}
    ]
  end

  def add_deployment_version_advanced_option_types
    []
  end

  def update_deployment_version_option_types
    add_deployment_version_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def update_deployment_version_advanced_option_types
    add_deployment_version_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

end
