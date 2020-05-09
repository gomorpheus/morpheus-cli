require 'morpheus/cli/cli_command'

class Morpheus::Cli::Projects
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper
  # include Morpheus::Cli::InfrastructureHelper
  # include Morpheus::Cli::AccountsHelper

  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @projects_interface = @api_client.projects
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
    @clouds_interface = @api_client.clouds
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    instance_ids, server_ids, cloud_ids, resource_ids, owner_ids = nil, nil, nil, nil, nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--instances [LIST]', Array, "Filter by Instance, comma separated list of instance names or IDs.") do |list|
        instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--servers [LIST]', Array, "Filter by Server, comma separated list of server (host) names or IDs.") do |list|
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--clouds [LIST]', Array, "Filter by Cloud, comma separated list of cloud (zone) names or IDs.") do |list|
        cloud_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--resources [LIST]', Array, "Filter by Resources, comma separated list of resource IDs.") do |list|
        resource_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--owners [LIST]', Array, "Owner, comma separated list of usernames or IDs.") do |list|
        owner_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
List projects.
EOT
    end
    optparse.parse!(args)
    #verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    options[:phrase] = args.join(' ') if args.count > 0 && params[:phrase].nil? # pass args as phrase, every list command should do this
    params.merge!(parse_list_options(options))
    params['instanceId'] = parse_instance_id_list(instance_ids) if instance_ids
    # todo server and cloud, missing parse_server_id_list() too
    params['serverId'] = parse_server_id_list(server_ids) if server_ids
    params['cloudId'] = parse_cloud_id_list(cloud_ids) if cloud_ids
    params['resourceId'] = parse_resource_id_list(resource_ids) if resource_ids
    params['ownerId'] = parse_user_id_list(owner_ids) if owner_ids
    @projects_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @projects_interface.dry.list(params)
      return
    end
    json_response = @projects_interface.list(params)
    projects = json_response['projects']
    render_response(json_response, options, 'projects') do
      title = "Morpheus Projects"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if projects.empty?
        print yellow,"No projects found.",reset,"\n"
      else
        print cyan
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"DESCRIPTION" => lambda {|it| it['description'] } },
          {"INSTANCES" => lambda {|it| it['instances'].size rescue '' } },
          {"SERVERS" => lambda {|it| it['servers'].size rescue '' } },
          {"CLOUDS" => lambda {|it| it['clouds'].size rescue '' } },
          {"RESOURCES" => lambda {|it| it['resources'].size rescue '' } },
          {"OWNER" => lambda {|it| it['owner'] ? it['owner']['username'] : '' } },
          {"DATE CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
          {"LAST UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
        ]
        print as_pretty_table(projects, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if projects.empty?
      return 1, "No projects found"
    else
      return 0, nil
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[project]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = <<-EOT
Get details about a project.
[project] is required. This is the name or id of a project.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end
  
  def _get(id, options)
    @projects_interface.setopts(options)
    if options[:dry_run]
      if id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @projects_interface.dry.get(id.to_i)
      else
        print_dry_run @projects_interface.dry.get({name: id})
      end
      return
    end
    project = find_project_by_name_or_id(id)
    exit 1 if project.nil?
    # refetch it by id
    json_response = {'project' => project}
    unless id.to_s =~ /\A\d{1,}\Z/
      json_response = @projects_interface.get(project['id'])
    end
    project = json_response['project']
    render_response(json_response, options, 'project') do
      print_h1 "Project Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Tags" => lambda {|it| it['tags'] ? it['tags'].collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
        "Owner" => lambda {|it| it['owner'] ? it['owner']['username'] : '' },
        "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, project)
      
      project_instances = project["instances"]
      if project_instances && project_instances.size > 0
        print_h2 "Instances"
        print cyan
        print as_pretty_table(project_instances, [:id, :name], options)
      end

      project_hosts = project["servers"] || project["hosts"]
      if project_hosts && project_hosts.size > 0
        print_h2 "Hosts"
        print cyan
        print as_pretty_table(project_hosts, [:id, :name], options)
      end

      project_clouds = project["clouds"] || project["zones"]
      if project_clouds && project_clouds.size > 0
        print_h2 "Clouds"
        print cyan
        print as_pretty_table(project_clouds, [:id, :name], options)
      end

      project_resources = project["resources"] || project["accountResources"]
      if project_resources && project_resources.size > 0
        print_h2 "Resources"
        print cyan
        print as_pretty_table(project_resources, [:id, :name], options)
      end

      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    exit_code, err = 0, nil
    params, options, payload = {}, {}, {}
    project_name, description, metadata, instance_ids, server_ids, cloud_ids, resource_ids = nil, nil, nil, nil, nil, nil, nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name NAME', String, "Project Name" ) do |val|
        project_name = val
      end
      opts.on('--description NAME', String, "Project Description" ) do |val|
        description = val
      end
      opts.on('--tags TAGS', String, "Tags in the format 'name:value, name:value'") do |val|
        metadata = val
      end
      opts.on('--instances [LIST]', Array, "Instances, comma separated list of instance names or IDs.") do |list|
        instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--servers [LIST]', Array, "Servers, comma separated list of server (host) names or IDs.") do |list|
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--clouds [LIST]', Array, "Clouds, comma separated list of cloud names or IDs.") do |list|
        cloud_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--resources [LIST]', Array, "Resources, comma separated list of resource IDs.") do |list|
        resource_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a project.
[name] is required. This is the name of the new project.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    if args[0]
      project_name = args[0]
    end
    connect(options)
    exit_code, err = 0, nil
    # construct payload
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'project' => parse_passed_options(options)})
    else
      payload['project'] = {}
      payload.deep_merge!({'project' => parse_passed_options(options)})
      payload['project']['name'] = project_name ? project_name : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Project Name'}], options[:options], @api_client)['name']
      payload['project']['description'] = description ? description : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Project Description'}], options[:options], @api_client)['description']
      # metadata tags
      if metadata
        metadata = parse_metadata(metadata)
        payload['project']['tags'] = metadata if metadata
      else
        metadata = prompt_metadata(options)
        payload['project']['tags'] = metadata if metadata
      end
      # --instances
      if instance_ids
        payload['project']['instances'] = parse_instance_id_list(instance_ids).collect { |it| {'id': it.to_i} }
      end
      # --servers
      if server_ids
        payload['project']['servers'] = parse_server_id_list(server_ids).collect { |it| {'id': it.to_i} }
      end
      # --clouds
      if cloud_ids
        payload['project']['clouds'] = parse_cloud_id_list(cloud_ids).collect { |it| {'id': it.to_i} }
      end
      # --resources
      if resource_ids
        payload['project']['resources'] = parse_resource_id_list(resource_ids).collect { |it| {'id': it.to_i} }
      end
    end
    @projects_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @projects_interface.dry.create(payload)
      return
    end
    json_response = @projects_interface.create(payload)
    project = json_response['project']
    render_response(json_response, options, 'project') do
      print_green_success "Project #{project['name']} created"
      exit_code, err = get([project['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return exit_code, err
  end

  def update(args)
    exit_code, err = 0, nil
    params, options, payload = {}, {}, {}
    project_name, description, metadata, add_metadata, remove_metadata = nil, nil, nil, nil, nil
    instance_ids, server_ids, cloud_ids, resource_ids = nil, nil, nil, nil
    add_instance_ids, remove_instance_ids = nil, nil
    add_server_ids, remove_server_ids = nil, nil
    add_cloud_ids, remove_cloud_ids = nil, nil
    add_resource_ids, remove_resource_ids = nil, nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[project] [options]")
      opts.on('--name NAME', String, "Project Name" ) do |val|
        project_name = val
      end
      opts.on('--description NAME', String, "Project Description" ) do |val|
        description = val
      end
      opts.on('--tags [TAGS]', String, "Project Tags in the format 'name:value, name:value'. This replaces all project tags.") do |val|
        metadata = val ? val : []
      end
      opts.on('--add-tags TAGS', String, "Add Project Tags in the format 'name:value, name:value'. This will add/update project tags.") do |val|
        add_metadata = val
      end
      opts.on('--remove-tags TAGS', String, "Remove Project Tags in the format 'name, name:value'. This removes project tags, the :value component is optional and must match if passed.") do |val|
        remove_metadata = val
      end
      opts.on('--instances [LIST]', Array, "Instances, comma separated list of instance names or IDs.") do |list|
        instance_ids = list ? list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq : []
      end
      opts.on('--add-instances LIST', Array, "Add Instances, comma separated list of instance names or IDs to add.") do |list|
        add_instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--remove-instances LIST', Array, "Remove Instances, comma separated list of instance names or IDs to remove.") do |list|
        remove_instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--servers [LIST]', Array, "Servers, comma separated list of server (host) names or IDs.") do |list|
        server_ids = list ? list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq : []
      end
      opts.on('--add-servers LIST', Array, "Add Servers, comma separated list of server names or IDs to add.") do |list|
        add_server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--remove-servers LIST', Array, "Remove Servers, comma separated list of server names or IDs to remove.") do |list|
        remove_server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--clouds [LIST]', Array, "Clouds, comma separated list of cloud names or IDs.") do |list|
        cloud_ids = list ? list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq : []
      end
      opts.on('--add-clouds LIST', Array, "Add Clouds, comma separated list of cloud names or IDs to add.") do |list|
        add_cloud_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--remove-clouds LIST', Array, "Remove Clouds, comma separated list of cloud names or IDs to remove.") do |list|
        remove_cloud_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--resources [LIST]', Array, "Resources, comma separated list of resource names or IDs.") do |list|
        resource_ids = list ? list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq : []
      end
      opts.on('--add-resources LIST', Array, "Add Resources, comma separated list of resource names or IDs to add.") do |list|
        add_resource_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--remove-resources LIST', Array, "Remove Resources, comma separated list of resource names or IDs to remove.") do |list|
        remove_resource_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a project.
[project] is required. This is the name or id of a project.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    exit_code, err = 0, nil
    project = find_project_by_name_or_id(args[0])
    return 1, "project not found by '#{args[0]}'" if project.nil?
    # construct payload
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'project' => parse_passed_options(options)})
    else
      payload['project'] = {}
      payload.deep_merge!({'project' => parse_passed_options(options)})
      payload['project']['name'] = project_name if project_name
      payload['project']['description'] = description if description
      # metadata tags
      if metadata
        payload['project']['tags'] = parse_metadata(metadata)
      end
      if add_metadata
        payload['project']['addTags'] = parse_metadata(add_metadata)
      end
      if remove_metadata
        payload['project']['removeTags'] = parse_metadata(remove_metadata)
      end
      # --instances
      if instance_ids
        payload['project']['instances'] = parse_instance_id_list(instance_ids).collect { |it| {'id': it.to_i} }
      end
      if add_instance_ids
        payload['project']['addInstances'] = parse_instance_id_list(add_instance_ids).collect { |it| {'id': it.to_i} }
      end
      if remove_instance_ids
        payload['project']['removeInstances'] = parse_instance_id_list(remove_instance_ids).collect { |it| {'id': it.to_i} }
      end
      # --servers
      if server_ids
        payload['project']['servers'] = parse_server_id_list(server_ids).collect { |it| {'id': it.to_i} }
      end
      if add_server_ids
        payload['project']['addServers'] = parse_server_id_list(add_server_ids).collect { |it| {'id': it.to_i} }
      end
      if remove_server_ids
        payload['project']['removeServers'] = parse_server_id_list(remove_server_ids).collect { |it| {'id': it.to_i} }
      end
      # --clouds
      if cloud_ids
        cloud_ids = parse_cloud_id_list(cloud_ids)
        return 1, "clouds not found" if cloud_ids.nil?
        payload['project']['clouds'] = cloud_ids.collect { |it| {'id': it.to_i} }
      end
      if add_cloud_ids
        add_cloud_ids = parse_cloud_id_list(add_cloud_ids)
        return 1, "clouds not found" if add_cloud_ids.nil?
        payload['project']['addClouds'] = add_cloud_ids.collect { |it| {'id': it.to_i} }
      end
      if remove_cloud_ids
        remove_cloud_ids = parse_cloud_id_list(remove_cloud_ids)
        return 1, "clouds not found" if remove_cloud_ids.nil?
        payload['project']['removeClouds'] = remove_cloud_ids.collect { |it| {'id': it.to_i} }
      end
      # --resources
      if resource_ids
        payload['project']['resources'] = parse_resource_id_list(resource_ids).collect { |it| {'id': it.to_i} }
      end
      if add_resource_ids
        add_resource_ids = parse_resource_id_list(add_resource_ids)
        return 1, "resources not found" if add_resource_ids.nil?
        payload['project']['addResources'] = add_resource_ids.collect { |it| {'id': it.to_i} }
      end
      if remove_resource_ids
        remove_resource_ids = parse_resource_id_list(remove_resource_ids)
        return 1, "resources not found" if remove_resource_ids.nil?
        payload['project']['removeResources'] = remove_resource_ids.collect { |it| {'id': it.to_i} }
      end
    end
    @projects_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @projects_interface.dry.update(project['id'], payload)
      return
    end
    json_response = @projects_interface.update(project['id'], payload)
    project = json_response['project']
    render_response(json_response, options, 'project') do
      print_green_success "Project #{project['name']} updated"
      exit_code, err = get([project['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return exit_code, err
  end

  def remove(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[project]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      # opts.on( '-f', '--force', "Force Delete" ) do
      #   params[:force] = true
      # end
      opts.footer = <<-EOT
Delete a project.
[project] is required. This is the name or id of a project.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    exit_code, err = 0, nil
    project = find_project_by_name_or_id(args[0])
    return 1, "project not found by '#{args[0]}'" if project.nil?
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the project #{project['name']}?")
      return 9, "aborted command"
    end
    @projects_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @projects_interface.dry.destroy(project['id'], params)
      return
    end
    json_response = @projects_interface.destroy(project['id'], params)
    render_response(json_response, options) do
      print_green_success "Project #{project['name']} removed"
    end
    return exit_code, err
  end

  private

  def find_project_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_project_by_id(val)
    else
      return find_project_by_name(val)
    end
  end

  def find_project_by_id(id)
    begin
      json_response = @projects_interface.get(id.to_i)
      return json_response['project']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Project not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_project_by_name(name)
    projects = @projects_interface.list({name: name.to_s})['projects']
    if projects.empty?
      print_red_alert "Project not found by name #{name}"
      return nil
    elsif projects.size > 1
      print_red_alert "#{projects.size} projects by name #{name}"
      print_error "\n"
      puts_error as_pretty_table(projects, [:id, :name], {color:red})
      print_red_alert "Try passing ID instead"
      return nil
    else
      return projects[0]
    end
  end

  def find_project_type_by_name(val)
    raise "find_project_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
    @all_project_types ||= @projects_interface.list_types({max:1000})['projectTypes']

    if @all_project_types.nil? && !@all_project_types.empty?
      print_red_alert "No project types found"
      return nil
    end
    matching_project_types = @all_project_types.select { |it| val && (it['name'] == val || it['code'] == val ||  it['id'].to_s == val.to_s) }
    if matching_project_types.size == 1
      return matching_project_types[0]
    elsif matching_project_types.size == 0
      print_red_alert "Project Type not found by '#{val}'"
    else
      print_red_alert "#{matching_project_types.size} project types found by name #{name}"
      rows = matching_project_types.collect do |it|
        {id: it['id'], name: it['name'], code: it['code']}
      end
      print "\n"
      puts as_pretty_table(rows, [:name, :code], {color:red})
      return nil
    end
  end

  def update_project_option_types(project_type)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 0}
    ] + project_type['optionTypes']
  end


end
