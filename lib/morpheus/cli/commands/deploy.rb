require 'morpheus/cli/cli_command'

class Morpheus::Cli::Deploy
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::DeploymentsHelper

  set_command_name :deploy
  set_command_description "Deploy to an instance from a morpheus.yml file."

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @instances_interface = @api_client.instances
    @deploy_interface = @api_client.deploy
    @deployments_interface = @api_client.deployments
  end

  def handle(args)
    options={}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus deploy [environment]"
      build_common_options(opts, options, [:auto_confirm, :quiet, :remote, :dry_run])
      opts.footer = <<-EOT
Deploy to an instance using the morpheus.yml file, located in the working directory.
[environment] is optional. Merge settings under environments.{environment}. Default is no environment.

First the morpheus.yml YAML file is parsed, merging the specified environment's nested settings.
The specified instance must exist and the specified deployment version must not exist.
If the settings are valid, the new deployment version will be created.
If is a file type deployment, all the discovered files are uploaded to the new deployment version.
Finally, it deploys the new version to the instance using any specified config options.

The morpheus.yml should be located in the working directory.
This YAML file contains the settings that specify how to execute the deployment.

File Settings
==================

* name - (required) The instance name being deployed to, also the default name of the deployment.
* version - (required) The version identifier of the deployment being created (userVersion)
* deployment - The name of the deployment being created, name is used by default
* type - The type of deployment, file, 'git' or 'fetch', default is 'file'.
* script - The initial script to run, happens before finding the files to be uploaded.
* files - (required) List of file patterns to use for uploading files and their target destination. 
          Each item should contain path and pattern, path may be relative to the working directory, default pattern is: '**/*'
          only applies to type 'file'
* url - (required) The url to fetch files from, only applies to types 'git' and 'fetch'.
* ref - The git reference, default is master (main), only applies to type git.
* config - Map of deployment config options depending on deployment type
* options - alias for config
* post_script - A post operation script to be run on the local machine
* stage_only - If set to true the deploy will only be staged and not actually run
* environments - Map of objects that contain nested properties for each environment name

It is possible to nest these properties in an "environments" map to override based on a passed environment.

Example
==================

name: mysite
version: 5.0
script: "rake build"
files: 
- path: build
environments:
  production:
    files:
    - path: production-build


Git Example
==================

name: morpheus-apidoc
version: 5.0.0
type: git
url: "https://github.com/gomorpheus/morpheus-apidoc"

EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    
    environment = default_deploy_environment
    if args.count > 0
      environment = args[0]
    end
    if load_deploy_file().nil?
      raise_command_error "Morpheus Deploy File `morpheus.yml` not detected. Please create one and try again."
    end

    # Parse and validate config, need instance + deployment + version + files
    # name can be specified as a single value for both instance and deployment

    deploy_args = merged_deploy_args(environment)

    instance_name = deploy_args['name']
    if deploy_args['instance'].is_a?(String)
      instance_name = deploy_args['instance']
    end
    if instance_name.nil?
      raise_command_error "Instance not specified. Please specify the instance name and try again."
    end

    deployment_name = deploy_args['name'] || instance_name
    if deploy_args['deployment'].is_a?(String)
      deployment_name = deploy_args['deployment']
    end
    
    version_number = deploy_args['version']
    if version_number.nil?
      raise_command_error "Version not specified. Please specify the version and try again."
    end

    instance_results = @instances_interface.list(name: instance_name)
    if instance_results['instances'].empty?
      raise_command_error "Instance not found by name '#{instance_name}'"
    end
    instance = instance_results['instances'][0]
    instance_id = instance['id']

    # auto detect type, default to file
    deploy_type = deploy_args['type'] || deploy_args['deployType']
    if deploy_type.nil?
      if deploy_args['gitUrl']
        deploy_type = 'git'
      elsif deploy_args['fetchUrl'] || deploy_args['url']
        deploy_type = 'fetch'
      end
    end
    if deploy_type.nil?
      deploy_type = "file"
    end
    deploy_url = deploy_args['url'] || deploy_args['fetchUrl'] || deploy_args['gitUrl']
    if deploy_url.nil? && (deploy_type == "git" || deploy_type == "fetch")
      raise_command_error "Deploy type '#{deploy_type}' requires a url to be specified"
    end
    #deploy_type = "file" if deploy_type.to_s.downcase == "files"

    deploy_config = deploy_args['options'] || deploy_args['config']

    # ok do it
    # fetch/create deployment, create deployment version, upload files, and deploy it to instance.

    unless options[:quiet]

      print_h1 "Morpheus Deployment", options

      columns = {
        "Instance" => :name,
        "Deployment" => :deployment,
        "Version" => :version,
        "Deploy Type" => :type,
        "Script" => :script,
        "Post Script" => :post_script,
        "Files" => :files,
        "Git Url" => :git_url,
        "Git Ref" => :git_ref,
        "Fetch Url" => :fetch_url,
        "Environment" => :environment,
      }
      pretty_file_config = deploy_args['files'] ? deploy_args['files'].collect {|it|
        [(it['path'] ? "path: #{it['path']}" : nil), (it['pattern'] ? "pattern: #{it['pattern']}" : nil)].compact.join(", ")
      }.join(", ") : "(none)"
      deploy_settings = {
        :name => instance_name,
        :deployment => deployment_name,
        :version => version_number,
        :script => deploy_args['script'],
        :post_script => deploy_args['post_script'],
        :files => pretty_file_config,
        :type => format_deploy_type(deploy_type),
        :git_url => deploy_args['gitUrl'] || (deploy_type == "git" ? deploy_args['url'] : nil),
        :git_ref => deploy_args['gitRef'] || (deploy_type == "git" ? deploy_args['ref'] : nil),
        :fetch_url => deploy_args['fetchUrl'] || (deploy_type == "fetch" ? deploy_args['url'] : nil),
        # :files => deploy_args['files'],
        # :files => deploy_files.size,
        # :file_config => (deploy_files.size == 1 ? deploy_files[0][:destination] : deploy_args['files'])
        :environment => environment
      }
      columns.delete("Script") if deploy_settings[:script].nil?
      columns.delete("Post Script") if deploy_settings[:post_script].nil?
      columns.delete("Environment") if deploy_settings[:environment].nil?
      columns.delete("Files") if deploy_type != "file" && deploy_type != "files"
      columns.delete("Git Url") if deploy_settings[:git_url].nil?
      columns.delete("Git Ref") if deploy_settings[:git_ref].nil?
      columns.delete("Fetch Url") if deploy_settings[:fetch_url].nil?
      print_description_list(columns, deploy_settings)
      print reset, "\n"

      if deploy_config
        print_h2 "Config Options", options
        print cyan
        puts as_json(deploy_config)
        print "\n\n", reset
      end

    end # unless options[:quiet]

    if !deploy_args['script'].nil?
      # do this for dry run too since this is usually what creates the files to be uploaded
      unless options[:quiet]
        print cyan, "Executing Pre Deploy Script...", reset, "\n"
        puts "running command: #{deploy_args['script']}"
      end
      if !system(deploy_args['script'])
        raise_command_error "Error executing pre script..."
      end
    end

    # Find Files to Upload
    deploy_files = []
    if deploy_type == "file" || deploy_type == "files"
      if deploy_args['files'].nil? || deploy_args['files'].empty? || !deploy_args['files'].is_a?(Array)
        raise_command_error "Files not specified. Please specify the files to include, each item may specify a path or pattern of file(s) to upload"
      else
        #print "\n",cyan, "Finding Files...", reset, "\n"
        current_working_dir = Dir.pwd
        deploy_args['files'].each do |fmap|
          Dir.chdir(fmap['path'] || current_working_dir)
          files = Dir.glob(fmap['pattern'] || '**/*')
          files.each do |file|
            if File.file?(file)
              destination = file.split("/")[0..-2].join("/")
              # deploy_files << {filepath: File.expand_path(file), destination: destination}
              deploy_files << {filepath: File.expand_path(file), destination: file}
            end
          end
        end
        #print cyan, "Found #{deploy_files.size} Files to Upload!", reset, "\n"
        Dir.chdir(current_working_dir)
      end

      if deploy_files.empty?
        raise_command_error "0 files found for: #{deploy_args['files'].inspect}"
      else
        unless options[:quiet]
          print cyan, "Found #{deploy_files.size} Files to Upload!", reset, "\n"
        end
      end
    elsif deploy_type == "git"
      # make it work with simpler config, url instead of gitUrl
      if deploy_args['gitUrl'].nil? && deploy_args['url']
        deploy_args['gitUrl'] = deploy_args['url'] # .delete('url') maybe?
      end
      if deploy_args['gitRef'].nil? && deploy_args['ref']
        deploy_args['gitRef'] = deploy_args['ref'] # .delete('ref') maybe?
      end
      if deploy_args['gitRef'].nil?
        raise_command_error "fetchUrl not specified. Please specify the git url to fetch the deploy files from."
      end
      if deploy_args['gitRef'].nil?
        #raise_command_error "gitRef not specified. Please specify the git reference to use. eg. main"
        # deploy_args['gitRef'] = "main"
      end
    elsif deploy_type == "git"
      # make it work with simpler config, url instead of fetchUrl
      if deploy_args['fetchUrl'].nil? && deploy_args['url']
        deploy_args['fetchUrl'] = deploy_args['url'] # .delete('url') maybe?
      end
      if deploy_args['fetchUrl'].nil?
        raise_command_error "fetchUrl not specified. Please specify the url to fetch the deploy files from."
      end
      
    end

    confirm_warning = ""
    confirm_message = "Are you sure you want to perform this action?"
    if deploy_type == "file" || deploy_type == "files"
      confirm_warning = "This will create deployment #{deployment_name} version #{version_number} and deploy it to instance #{instance['name']}."
    elsif deploy_type == "git"
      confirm_warning = "This will create deployment #{deployment_name} version #{version_number} and deploy it to instance #{instance['name']}."
    elsif deploy_type == "fetch"
      confirm_warning = "This will create deployment #{deployment_name} version #{version_number} and deploy it to instance #{instance['name']}."
    end
    puts confirm_warning if !options[:quiet]
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm(confirm_message)
      return 9, "aborted command"
    end
    
    # Find or Create Deployment
    deployment = nil
    deployments = @deployments_interface.list(name: deployment_name)['deployments']

    @instances_interface.setopts(options)
    @deploy_interface.setopts(options)
    @deployments_interface.setopts(options)

    if deployments.size > 1
      raise_command_error "#{deployments.size} deployment versions found by deployment '#{name}'"
    elsif deployments.size == 1
      deployment = deployments[0]
      # should update here, eg description
    else
      # create it
      payload = {
        'deployment' => {
          'name' => deployment_name
        } 
      }
      payload['deployment']['description'] = deploy_args['description'] if deploy_args['description']
      
      if options[:dry_run]
        print_dry_run @deployments_interface.dry.create(payload)
        # return 0, nil
        deployment = {'id' => ':deploymentId', 'name' => deployment_name}
      else
        json_response = @deployments_interface.create(payload)
        deployment = json_response['deployment']
      end
    end

    # Find or Create Deployment Version
    # Actually, for now this this errors if the version already exists, but it should update it.

    @deployments_interface = @api_client.deployments
    deployment_version = nil
    if options[:dry_run]
      print_dry_run @deployments_interface.dry.list_versions(deployment['id'], {userVersion: version_number})
      # return 0, nil
      #deployment_versions =[{'id' => ':versionId', 'version' => version_number}]
      deployment_versions = []
    else
      deployment_versions = @deployments_interface.list_versions(deployment['id'], {userVersion: version_number})['versions']
      @deployments_interface.setopts(options)
    end
    

    if deployment_versions.size > 0
      raise_command_error "Deployment '#{deployment['name']}' version '#{version_number}' already exists. Specify a new version or delete the existing version."
    # if deployment_versions.size > 1
    #   raise_command_error "#{deployment_versions.size} versions found by version '#{name}'"
    # elsif deployment_versions.size == 1
    #   deployment_version = deployment_versions[0]
    #   # should update here, eg description
    else
      # create it
      payload = {
        'version' => {
          'userVersion' => version_number,
          'deployType' => deploy_type
        } 
      }
      payload['version']['fetchUrl'] = deploy_args['fetchUrl'] if deploy_args['fetchUrl']
      payload['version']['gitUrl'] = deploy_args['gitUrl'] if deploy_args['gitUrl']
      payload['version']['gitRef'] = deploy_args['gitRef'] if deploy_args['gitRef']
      
      if options[:dry_run]
        print_dry_run @deployments_interface.dry.create_version(deployment['id'], payload)
        # return 0, nil
        deployment_version = {'id' => ':versionId', 'version' => version_number}
      else
        json_response = @deployments_interface.create_version(deployment['id'], payload)
        deployment_version = json_response['version']
      end
    end

    
    # Upload Files
    if deploy_type == "file" || deploy_type == "files"
      if deploy_files && !deploy_files.empty?
        print "\n",cyan, "Uploading #{deploy_files.size} Files...", reset, "\n" if !options[:quiet]
        current_working_dir = Dir.pwd
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
        print cyan, "Upload Complete!", reset, "\n" if !options[:quiet]
        Dir.chdir(current_working_dir)
      else
        print "\n",cyan, "0 files to upload", reset, "\n" if !options[:quiet]
      end
    end

    if !deploy_args['post_script'].nil?
      print cyan, "Executing Post Script...", reset, "\n" if !options[:quiet]
      puts "running command: #{deploy_args['post_script']}" if !options[:quiet]
      if !system(deploy_args['post_script'])
        raise_command_error "Error executing post script..."
      end
    end

    # JD: restart for evars eh?
    if deploy_args['env']
      evars = []
      deploy_args['env'].each_pair do |key, value|
        evars << {name: key, value: value, export: false}
      end
      payload = {envs: evars}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create_env(instance_id, payload)
        print_dry_run @instances_interface.dry.restart(instance_id)
      else
        @instances_interface.create_env(instance_id, payload)
        @instances_interface.restart(instance_id)
      end
    end
    # Create the AppDeploy, this does the deploy async (as of 4.2.2-3)
    payload = {'appDeploy' => {} }
    payload['appDeploy']['versionId'] = deployment_version['id']
    if deploy_args['options']
      payload['appDeploy']['config'] = deploy_args['options']
    end
    # stageOnly means do not actually deploy yet, can invoke @deploy_interface.deploy(deployment['id']) later
    # there is no cli command for that yet though..
    stage_only = deploy_args['stage'] || deploy_args['stage_deploy'] || deploy_args['stage_only'] || deploy_args['stageOnly']
    if stage_only
      payload['appDeploy']['stageOnly'] = true
    end
    # config/options to apply to deployment
    if deploy_config
      payload['appDeploy']['config'] = deploy_config
    end
    app_deploy_id = nil
    if options[:dry_run]
      print_dry_run @deploy_interface.dry.create(instance_id, payload)
      # return 0, nil
      app_deploy_id = ':appDeployId'
    else
      # Create a new appDeploy record, without stageOnly, this actually does the deployment
      #print cyan, "Deploying #{deployment_name} version #{version_number} to instance #{instance_name} ...", reset, "\n"
      deploy_result = @deploy_interface.create(instance_id, payload)
      app_deploy = deploy_result['appDeploy']
      app_deploy_id = app_deploy['id']
      if !options[:quiet]
        if app_deploy['status'] == 'staged'
          print_green_success "Staged Deploy #{deployment_name} version #{version_number} to instance #{instance_name}"
        else
          print_green_success "Deploying #{deployment_name} version #{version_number} to instance #{instance_name}"
        end
      end
    end
    return 0, nil
  end

  protected

  # Loads a morpheus.yml file from within the current working directory.
  # This file contains information necessary to perform a deployment via the cli.
  #
  # === Example File Attributes
  # * +script+ - The initial script to run before uploading files
  # * +name+ - The instance name we are deploying to (can be overridden in CLI)
  # * +files+ - List of file patterns to use for uploading files and their target destination
  # * +options+ - Map of deployment options depending on deployment type
  # * +post_script+ - A post operation script to be run on the local machine
  # * +stage_deploy+ - If set to true the deploy will only be staged and not actually run
  #
  # +NOTE: + It is also possible to nest these properties in an "environments" map to override based on a passed environment deploy name
  #
  def load_deploy_file
    if !File.exist? "morpheus.yml"
      puts "No morpheus.yml file detected in the current directory. Nothing to do."
      return nil
    end

    @deploy_file = YAML.load_file("morpheus.yml")
    return @deploy_file
  end

  def merged_deploy_args(environment)
    deploy_args = @deploy_file.reject { |key,value| key == 'environment'}
    if environment && !@deploy_file['environment'].nil? && !@deploy_file['environment'][environment].nil?
      deploy_args = deploy_args.merge(@deploy_file['environment'][environment])
    end
    return deploy_args
  end

  def default_deploy_environment
    nil
  end

end
