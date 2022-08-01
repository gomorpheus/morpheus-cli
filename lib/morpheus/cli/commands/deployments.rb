require 'morpheus/cli/cli_command'

class Morpheus::Cli::Deployments
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::DeploymentsHelper

  set_command_description "View and manage deployments, including versions and files."

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :list_versions, :get_version, :add_version, :update_version, :remove_version
  register_subcommands :list_files, :upload, :remove_file
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
        deployment = find_deployment_by_name_or_id(id)
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
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the deployment #{deployment['name']}?")
      return 9, "aborted command"
    end
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
      opts.on(nil, '--no-files', "Do not show files") do
        options[:no_files] = true
      end
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
      deployment_version = find_deployment_version_by_name_or_id(deployment['id'], id)
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
    deploy_type = deployment_version['deployType'] || deployment_version['type']
    deployment_files_response = nil
    deployment_files = nil
    if options[:no_files] != true
      deployment_files_response = @deployments_interface.list_files(deployment['id'], deployment_version['id'], params)
      deployment_files = deployment_files_response.is_a?(Array) ? deployment_files_response : deployment_files_response['files']
    end
    render_response(json_response, options, 'version') do
      # print_h1 "Deployment Version Details", [deployment['name']], options
      print_h1 "Deployment Version Details", [], options
      print cyan
      #columns = deployment_version_column_definitions
      columns = {
        "ID" => 'id',
        "Deployment" => lambda {|it| deployment['name'] },
        "Version" => lambda {|it| format_deployment_version_number(it) },
        "Deploy Type" => lambda {|it| it['deployType'] },
        "URL" => lambda {|it| it['fetchUrl'] || it['gitUrl'] || it['url'] },
        "Ref" => lambda {|it| it['gitRef'] || it['ref'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      if deployment_version['deployType'] == 'git'
        options[:no_files] = true
      elsif deployment_version['deployType'] == 'fetch'
        options[:no_files] = true
        columns['Fetch URL'] = columns['URL']
        columns.delete('Ref')
      else
        columns.delete('URL')
        columns.delete('Ref')
      end
      print_description_list(columns, deployment_version)
      print reset,"\n"

      if options[:no_files] != true
        print_h2 "Deployment Files", options
        if !deployment_files || deployment_files.empty?
          print cyan,"No files found.",reset,"\n"
        else
          print as_pretty_table(deployment_files, deployment_file_column_definitions.upcase_keys!, options)
          print_results_pagination({size:deployment_files.size,total:deployment_files.size.to_i})
        end
        print reset,"\n"
      end

    end
    return 0, nil
  end

  def add_version(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [options]")
      opts.on('-t', '--type CODE', String, "Deploy Type, file, git or fetch, default is file.") do |val|
        options[:options]['deployType'] = val
      end
      build_option_type_options(opts, options, add_deployment_version_option_types)
      opts.add_hidden_option('--deployType')
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
    return 1, "deployment not found" if deployment.nil?
    id = args[1]
    deployment_version = find_deployment_version_by_name_or_id(deployment['id'], id)
    return 1, "version not found" if deployment_version.nil?
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the deployment version #{format_deployment_version_number(deployment_version)}?")
      return 9, "aborted command"
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.destroy_version(deployment['id'], deployment_version['id'], params)
      return
    end
    json_response = @deployments_interface.destroy_version(deployment['id'], deployment_version['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed deployment #{deployment['name']} version #{format_deployment_version_number(deployment_version)}"
    end
    return 0, nil
  end

  def list_files(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [path] [options]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List files in a deployment version.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the deployment version identifier
[path] is optional. This is a the directory to search for files under.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2, max: 3)
    connect(options)
    params.merge!(parse_list_options(options))
    deployment = find_deployment_by_name_or_id(args[0])
    return 1, "deployment not found for '#{args[0]}'" if deployment.nil?
    deployment_version = find_deployment_version_by_name_or_id(deployment['id'], args[1])
    return 1, "deployment version not found for '#{args[1]}'" if deployment_version.nil?
    if args[2]
      params['filePath'] = args[2]
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.list_files(deployment['id'], deployment_version['id'], params)
      return
    end
    json_response = @deployments_interface.list_files(deployment['id'], deployment_version['id'], params)
    # odd, api used to just return an array
    deployment_files = json_response.is_a?(Array) ? json_response : json_response['files']
    render_response(json_response, options) do
      print_h1 "Deployment Files", ["#{deployment['name']} #{format_deployment_version_number(deployment_version)}"]
      if !deployment_files || deployment_files.empty?
        print cyan,"No files found.",reset,"\n"
      else
        print as_pretty_table(deployment_files, deployment_file_column_definitions.upcase_keys!, options)
        #print_results_pagination(json_response)
        print_results_pagination({size:deployment_files.size,total:deployment_files.size.to_i})
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def upload(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [files]")
      opts.on('--files LIST', String, "Files to upload") do |val|
        val_list = val.to_s.split(",").collect {|it| it.to_s.strip }.select { |it| it != "" }
        options[:files] ||= []
        options[:files] += val_list
      end
      opts.on('--workdir DIRECTORY', String, "Working directory to switch to before uploading files, determines the paths of the uploaded files. The current working directory of your terminal is used by default.") do |val|
        options[:workdir] = File.expand_path(val)
        if !File.directory?(options[:workdir])
          raise_command_error "invalid directory: #{val}"
        end
      end
      opts.on('--destination FILEPATH', String, "Destination filepath for file being uploaded, should include full filename and extension. Only applies when uploading a single file.") do |val|
        options[:destination] = val
      end
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Upload one or more files or directories to a deployment version.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the deployment version identifier
[files] is required. This is a list of files or directories to be uploaded. Glob pattern format supported eg. build/*.html
EOT
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, min:0, max:2)
    connect(options)

    # fetch deployment
    deployment = nil
    if args[0]
      deployment = find_deployment_by_name_or_id(args[0])
      return 1 if deployment.nil?
    else
      all_deployments = @deployments_interface.list(max:10000)['deployments']
      deployment_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deployment', 'fieldLabel' => 'Deployment', 'type' => 'select', 'required' => true, 'description' => 'Deployment identifier (name or ID)', 'optionSource' => lambda { |api_client, api_params|
        all_deployments.collect {|it| {'name' => it['name'], 'value' => it['id']} }
      }}], options[:options])['deployment']
      deployment = all_deployments.find {|it| deployment_id == it['id'] || deployment_id == it['name'] }
      raise_command_error "Deployment not found for '#{deployment_id}'" if deployment.nil?
    end

    # fetch deployment version
    deployment_version = nil
    if args[1]
      deployment_version = find_deployment_version_by_name_or_id(deployment['id'], args[1])
      return 1 if deployment_version.nil?
    else
      all_deployment_versions = @deployments_interface.list_versions(deployment['id'], {max:10000})['versions']
      deployment_version_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'version', 'fieldLabel' => 'Version', 'type' => 'select', 'required' => true, 'description' => 'Deployment Version identifier (version or ID) to upload files to', 'optionSource' => lambda { |api_client, api_params|
        all_deployment_versions.collect {|it| {'name' => it['version'] || it['userVersion'], 'value' => it['id']} }
      }}], options[:options])['version']
      deployment_version = all_deployment_versions.find {|it| deployment_version_id == it['id'] || deployment_version_id == it['userVersion'] || deployment_version_id == it['version'] }
      raise_command_error "Deployment Version not found for '#{deployment_version_id}'" if deployment_version.nil?
    end


    # Determine which files to find
    file_patterns = []
    # [files] is args 3 - N
    if args.size > 2
      file_patterns += args[2..-1]
    end
    if options[:files]
      file_patterns += options[:files]
    end
    if file_patterns.empty?
      #raise_command_error "Files not specified. Please specify files array, each item may specify a path or pattern of file(s) to upload", args, optparse
      file_patterns = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'files', 'fieldLabel' => 'Files', 'type' => 'text', 'required' => true, 'description' => 'Files or directories to upload'}], options[:options])['files'].to_s.split(",").collect {|it| it.to_s.strip }.select { |it| it != "" }
    end

    # Find Files to Upload
    deploy_files = []
    
    #print "\n",cyan, "Finding Files...", reset, "\n" unless options[:quiet]
    original_working_dir = Dir.pwd
    base_working_dir = options[:workdir] || original_working_dir
    begin
      file_patterns.each do |file_pattern|
        # start in the working directory
        # to preserve relative paths in upload file destinations
        # allow passing just build  instead  build/**/*
        Dir.chdir(base_working_dir)
        fmap = nil
        full_file_pattern = File.expand_path(file_pattern)
        if File.exists?(full_file_pattern)
          if File.directory?(full_file_pattern)
            fmap = {'path' => full_file_pattern, 'pattern' => '**/*'}
          else
            fmap = {'path' => File.dirname(full_file_pattern), 'pattern' => File.basename(full_file_pattern)}
          end
        else
          fmap = {'path' => nil, 'pattern' => file_pattern}
        end
        if fmap['path']
          Dir.chdir(File.expand_path(fmap['path']))
        end
        files = Dir.glob(fmap['pattern'] || '**/*')
        if files.empty?
          raise_command_error "Found 0 files for file pattern '#{file_pattern}'"
        end
        files.each do |file|
          if File.file?(file)
            destination = file.split("/")[0..-2].join("/")
            # deploy_files << {filepath: File.expand_path(file), destination: destination}
            # absolute path was given, so no path is given to the destination file
            # maybe apply options[:destination] as prefix here
            # actually just do destination.sub!(base_working_dir, '')
            if file[0].chr == "/"
              deploy_files << {filepath: File.expand_path(file), destination: File.basename(file)}
            else
              deploy_files << {filepath: File.expand_path(file), destination: file}
            end
          end
        end
      end
      #print cyan, "Found #{deploy_files.size} Files to Upload!", reset, "\n"
    rescue => ex
      # does not happen, just in case
      #print_error "An error occured while searching for files to upload: #{ex}"
      raise ex
    ensure
      Dir.chdir(original_working_dir)
    end
      
    # make sure we have something to upload.
    if deploy_files.empty?
      raise_command_error "0 files found for: #{file_patterns.join(', ')}"
    else
      unless options[:quiet]
        print cyan, "Found #{deploy_files.size} Files to Upload!", reset, "\n"
      end
    end

    # support uploading a local file to a custom destination
    # this only works for a single file right now, should be better
    # could try to add destination + filename
    # for now expect filename to be included in destination
    if options[:destination]
      if deploy_files.size == 1
        deploy_files[0][:destination] = options[:destination]
      else
        raise_command_error "--destination can only specified for a single file upload, not #{deploy_files} files.", args, optparse
      end
    end

    confirm_message = "Are you sure you want to upload #{deploy_files.size} files to deployment #{deployment['name']} #{format_deployment_version_number(deployment_version)}?"
    if deploy_files.size == 1
      confirm_message = "Are you sure you want to upload file #{deploy_files[0][:destination]} to deployment #{deployment['name']} #{format_deployment_version_number(deployment_version)}?"
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm(confirm_message)
      return 9, "aborted command"
    end

    @deployments_interface.setopts(options)

    # Upload Files
    if deploy_files && !deploy_files.empty?
      print "\n",cyan, "Uploading #{deploy_files.size} Files...", reset, "\n" if !options[:quiet]
      deploy_files.each do |f|
        destination = f[:destination]
        if options[:dry_run]
          print_dry_run @deployments_interface.upload_file(deployment['id'], deployment_version['id'], f[:filepath], f[:destination])
        else
          print cyan,"  - Uploading #{f[:destination]} ...", reset if !options[:quiet]
          upload_result = @deployments_interface.upload_file(deployment['id'], deployment_version['id'], f[:filepath], f[:destination])
          #print green + "SUCCESS" + reset + "\n" if !options[:quiet]
          print reset, "\n" if !options[:quiet]
        end
      end
      if options[:dry_run]
        return 0, nil
      end
      #print cyan, "Upload Complete!", reset, "\n" if !options[:quiet]
      if options[:quiet]
        return 0, nil
      else
        print_green_success "Upload Complete!"
        return get_version([deployment["id"], deployment_version['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    else
      raise_command_error "No files to upload!"
    end
  end

  def remove_file(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[deployment] [version] [file] [options]")
      opts.on( '-R', '--recursive', "Delete a directory and all of its files. This must be passed if specifying a directory." ) do
        # do_recursive = true
        params['force'] = true
      end
      opts.on( '-f', '--force', "Force delete, this will do a recursive delete of directories." ) do
        params['force'] = true
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a deployment file.
[deployment] is required. This is the name or id of a deployment.
[version] is required. This is the version identifier of a deployment version.
[file] is required. This is the name of the file to be deleted.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2, max:3)
    connect(options)
    deployment = find_deployment_by_name_or_id(args[0])
    return 1, "deployment not found" if deployment.nil?
    id = args[1]
    deployment_version = find_deployment_version_by_name_or_id(deployment['id'], id)
    return 1, "version not found" if deployment_version.nil?
    # could look it up here, or allow a directory instead of a single file
    filename = args[2]
    if filename.nil?
      #raise_command_error "Files not specified. Please specify files array, each item may specify a path or pattern of file(s) to upload", args, optparse
      filename = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'file', 'fieldLabel' => 'Files', 'type' => 'text', 'required' => true, 'description' => 'Files or directories to upload'}], options[:options])['file'].to_s #.split(",").collect {|it| it.to_s.strip }.select { |it| it != "" }
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the file #{filename}?")
      return 9, "aborted command"
    end
    @deployments_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.destroy_file(deployment['id'], deployment_version['id'], filename, params)
      return
    end
    json_response = @deployments_interface.destroy_file(deployment['id'], deployment_version['id'], filename, params)
    render_response(json_response, options) do
      print_green_success "Removed deployment file #{filename}"
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
      "Version" => lambda {|it| format_deployment_version_number(it) },
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
      {'fieldName' => 'deployType', 'fieldLabel' => 'Deploy Type', 'type' => 'select', 'optionSource' => 'deployTypes', 'required' => true, 'displayOrder' => 2, 'description' => 'This is the deployment version identifier (userVersion)', 'defaultValue' => 'file', 'code' => 'deployment.deployType'},
      {'fieldName' => 'fetchUrl', 'fieldLabel' => 'Fetch URL', 'type' => 'string', 'required' => true, 'displayOrder' => 3, 'description' => 'The URL to fetch the deployment file(s) from.', 'dependsOnCode' => 'deployment.deployType:fetch'},
      {'fieldName' => 'gitUrl', 'fieldLabel' => 'Git URL', 'type' => 'string', 'required' => true, 'displayOrder' => 4, 'description' => 'The URL to fetch the deployment file(s) from.', 'dependsOnCode' => 'deployment.deployType:git'},
      {'fieldName' => 'gitRef', 'fieldLabel' => 'Git Ref', 'type' => 'string', 'displayOrder' => 5, 'description' => 'The Git Reference to use, this the branch or tag name, defaults to master.', 'dependsOnCode' => 'deployment.deployType:git'}
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

  # Deployment Files

  def deployment_file_column_definitions
    {
      #"ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| (it['directory'] || it['isDirectory']) ? "directory" : (it["contentType"] || "file") },
      "Size" => lambda {|it| (it['directory'] || it['isDirectory']) ? "" : format_bytes_short(it['contentLength']) },
      #"Content Type" => lambda {|it| it['contentType'] },
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

end
