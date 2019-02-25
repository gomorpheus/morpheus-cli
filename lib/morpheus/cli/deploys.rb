# require 'yaml'
require 'io/console'
require 'rest_client'
require 'filesize'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Deploys
  include Morpheus::Cli::CliCommand

  set_command_name :deploy

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @deploy_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).deploy
  end

  def handle(args)
    deploy(args)
  end

  def deploy(args)
    options={}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus deploy [environment]"
      build_common_options(opts, options, [:remote, :dry_run])
      opts.footer = "Deploy to an environment using the morpheus.yml file, located in the working directory."
      # "todo: document me better!"
    end
    optparse.parse!(args)
    connect(options)
    environment = 'production' # yikes!
    if args.count > 0
      environment = args[0]
    end
    if load_deploy_file().nil?
      puts "Morpheus Deploy File `morpheus.yml` not detected. Please create one and try again."
      return
    end

    deploy_args = merged_deploy_args(environment)
    if deploy_args['name'].nil?
      puts "Instance not specified. Please specify the instance name and try again."
      return
    end

    instance_results = @instances_interface.get(name: deploy_args['name'])
    if instance_results['instances'].empty?
      puts "Instance not found by name #{args[0]}"
      return
    end
    instance = instance_results['instances'][0]
    instance_id = instance['id']
    print_h1 "Morpheus Deployment"
    if !deploy_args['script'].nil?
      print cyan, bold, "  - Executing Pre Deploy Script...", reset, "\n"

      if !system(deploy_args['script'])
        puts "Error executing pre script..."
        return
      end
    end
    @deploy_interface.setopts(options)
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @deploy_interface.create(instance_id)
    end
    # Create a new deployment record
    deploy_result = @deploy_interface.create(instance_id)
    app_deploy = deploy_result['appDeploy']
    deployment_id = app_deploy['id']

    # Upload Files
    print "\n",cyan, bold, "Uploading Files...", reset, "\n"
    current_working_dir = Dir.pwd
    deploy_args['files'].each do |fmap|
      Dir.chdir(fmap['path'] || current_working_dir)
      files = Dir.glob(fmap['pattern'] || '**/*')
      files.each do |file|
        if File.file?(file)
          print cyan,bold, "  - Uploading #{file} ...", reset, "\n"
          destination = file.split("/")[0..-2].join("/")
          if options[:dry_run]
            print_dry_run @deploy_interface.upload_file(deployment_id,file,destination)
          else
            upload_result = @deploy_interface.upload_file(deployment_id,file,destination)
          end
        end
      end
    end
    print cyan, bold, "Upload Complete!", reset, "\n"
    Dir.chdir(current_working_dir)

    if !deploy_args['post_script'].nil?
      print cyan, bold, "Executing Post Script...", reset, "\n"
      if !system(deploy_args['post_script'])
        puts "Error executing post script..."
        return
      end
    end

    deploy_payload = {}
    if deploy_args['env']
      evars = []
      deploy_args['env'].each_pair do |key, value|
        evars << {name: key, value: value, export: false}
      end
      payload = {envs: evars}
      if options[:dry_run]
        print_dry_run @instances_interface.create_env(instance_id, payload)
        print_dry_run @instances_interface.restart(instance_id)
      else
        @instances_interface.create_env(instance_id, payload)
        @instances_interface.restart(instance_id)
      end
    end
    if deploy_args['options']
      deploy_payload = {
        appDeploy: {
          config: deploy_args['options']
        }
      }
    end
    if options[:dry_run]
      print_dry_run @deploy_interface.deploy(deployment_id,deploy_payload)
    else
      print cyan, bold, "Deploying to Servers...", reset, "\n"
      @deploy_interface.deploy(deployment_id,deploy_payload)
      print cyan, bold, "Deploy Successful!", reset, "\n"
    end
    
  end
  def list(args)
  end

  def rollback(args)
  end

  # Loads a morpheus.yml file from within the current working directory.
  # This file contains information necessary in the project to perform a deployment via the cli
  #
  # === Example File Attributes
  # * +script+ - The initial script to run before uploading files
  # * +name+ - The instance name we are deploying to (can be overridden in CLI)
  # * +remote+ - Optional remote appliance name we are connecting to
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
    environment = environment || production

    deploy_args = @deploy_file.reject { |key,value| key == 'environment'}
    if !@deploy_file['environment'].nil? && !@deploy_file['environment'][environment].nil?
      deploy_args = deploy_args.merge(@deploy_file['environment'][environment])
    end
    return deploy_args
  end
end
