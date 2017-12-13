require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::StorageProvidersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'storage-providers'

  register_subcommands :list, :get, :add, :update, :remove
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @storage_providers_interface = @api_client.storage_providers
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List storage providers."
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.list(params)
        return
      end
      json_response = @storage_providers_interface.list(params)
      storage_providers = json_response["storageProviders"]
      if options[:include_fields]
        json_response = {"storageProviders" => filter_data(storage_providers, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(storage_providers, options)
        return 0
      end
      title = "Morpheus Storage Providers"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if storage_providers.empty?
        print cyan,"No storage providers found.",reset,"\n"
      else
        rows = storage_providers.collect {|storage_provider| 
          row = {
            id: storage_provider['id'],
            name: storage_provider['name'],
            provider: format_storage_provider_type(storage_provider), 
            bucket: format_bucket_name(storage_provider), 
            backups: storage_provider['defaultBackupTarget'] ? 'Yes' : 'No', 
            deployments: storage_provider['defaultDeploymentTarget'] ? 'Yes' : 'No', 
            virtualImages: storage_provider['defaultVirtualImageTarget'] ? 'Yes' : 'No', 
          }
          row
        }
        columns = [:id, :name, {:provider => {:display_name => "Provider Type".upcase} }, {:bucket => {:display_name => "Bucket Name".upcase} }, :backups, :deployments]
        if options[:include_fields]
          columns = options[:include_fields]
          rows = storage_providers
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "storage provider", :n_label => "storage providers"})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[storage-provider]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a storage provider." + "\n" +
                    "[storage-provider] is required. This is the name or id of a storage provider."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [storage-provider]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @storage_providers_interface.dry.get(args[0].to_i)
        else
          print_dry_run @storage_providers_interface.dry.list({name:args[0]})
        end
        return
      end
      storage_provider = find_storage_provider_by_name_or_id(args[0])
      return 1 if storage_provider.nil?
      json_response = {'storageProvider' => storage_provider}  # skip redundant request
      # json_response = @storage_providers_interface.get(storage_provider['id'])
      storage_provider = json_response['storageProvider']
      if options[:include_fields]
        json_response = {'storageProvider' => filter_data(storage_provider, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([storage_provider], options)
        return 0
      end
      print_h1 "Storage Provider Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| it['name'] },
        "Provider Type" => lambda {|it| format_storage_provider_type(it) },
        "Bucket Name" => lambda {|it| format_bucket_name(it) },
        "Default Backup Target" => lambda {|it| it['defaultBackupTarget'] ? 'Yes' : 'No' },
        "Default Deployment Target" => lambda {|it| it['defaultDeploymentTarget'] ? 'Yes' : 'No' },
        "Default Virtual Image Store" => lambda {|it| it['defaultVirtualImageTarget'] ? 'Yes' : 'No' },
        "Archive Snapshots" => lambda {|it| it['copyToStore'] ? 'Yes' : 'No' }
      }
      print_description_list(description_cols, storage_provider)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--name VALUE', String, "Name for this storage provider") do |val|
        options['name'] = val
      end
      opts.on('--type code', String, "Storage Provider Type Code") do |val|
        options['providerType'] = val
      end
      opts.on('--bucket-name VALUE', String, "Bucket Name") do |val|
        options['bucketName'] = val
      end
      opts.on('--default-backup-target [on|off]', String, "Default Backup Target") do |val|
        options['defaultBackupTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-deployment-target [on|off]', String, "Default Deployment Target") do |val|
        options['defaultDeploymentTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-virtual-image-target [on|off]', String, "Default Virtual Image Store") do |val|
        options['defaultVirtualImageTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--copy-to-store [on|off]', String, "Archive Snapshots") do |val|
        options['copyToStore'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new storage provider." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # support [name] as first argument
      if args[0]
        options['name'] = args[0]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for storage provider options
        payload = {
          'storageProvider' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['storageProvider'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['storageProvider']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this storage provider.'}], options)
          payload['storageProvider']['name'] = v_prompt['name']
        end

        # Storage Provider Type
        storage_provider_type_code = nil
        if options['type']
          storage_provider_type_code = options['type'].to_s
        elsif options['providerType']
          storage_provider_type_code = options['providerType'].to_s
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'providerType', 'fieldLabel' => 'Provider Type', 'type' => 'select', 'selectOptions' => get_storage_provider_types(), 'required' => true, 'description' => 'Choose a storage provider type.'}], options, @api_client, {})
          storage_provider_type_code = v_prompt['providerType'] unless v_prompt['providerType'].nil?
        end
        payload['storageProvider']['providerType'] = storage_provider_type_code

        # Provider Type Specific Options
        provider_type_option_types = nil
        if storage_provider_type_code == 's3'
          # print_h2 "Amazon S3 Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'accessKey', 'fieldLabel' => 'Access Key', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'secretKey', 'fieldLabel' => 'Secret Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'endpoint', 'fieldLabel' => 'Endpoint URL', 'type' => 'text', 'required' => false, 'description' => 'Optional endpoint URL if pointing to an object store other than amazon that mimics the Amazon S3 APIs.'},
          ]
        elsif storage_provider_type_code == 'azure'
          # print_h2 "Azure Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'storageAccount', 'fieldLabel' => 'Storage Account', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'storageKey', 'fieldLabel' => 'Storage Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''}
          ]
        elsif storage_provider_type_code == 'cifs'
          # print_h2 "CIFS Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'host', 'fieldLabel' => 'Host', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''}
          ]
        elsif storage_provider_type_code == 'local'
          # print_h2 "Local Storage Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'basePath', 'fieldLabel' => 'Storage Path', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'hidden', 'required' => true, 'description' => '', 'defaultValue' => '.'}
          ]
        elsif storage_provider_type_code == 'nfs'
          # print_h2 "NFSv3 Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'host', 'fieldLabel' => 'Host', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'exportFolder', 'fieldLabel' => 'Export Folder', 'type' => 'text', 'required' => false, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'hidden', 'required' => true, 'description' => '', 'defaultValue' => '/'}
          ]
        elsif storage_provider_type_code == 'openstack'
          # print_h2 "Openstack Swift Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'apiKey', 'fieldLabel' => 'API Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'region', 'fieldLabel' => 'Region', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'identityUrl', 'fieldLabel' => 'Identity URL', 'type' => 'text', 'required' => true, 'description' => ''},
          ]
        elsif storage_provider_type_code == 'rackspace'
          # print_h2 "Rackspace CDN Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'accessKey', 'fieldLabel' => 'Access Key', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'secretKey', 'fieldLabel' => 'Secret Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'endpoint', 'fieldLabel' => 'Endpoint URL', 'type' => 'text', 'required' => true, 'description' => 'Optional endpoint URL if pointing to an object store other than amazon that mimics the Amazon S3 APIs.'},
          ]
        else
          puts "warning: unrecognized storage provider type: '#{storage_provider_type_code}'"
        end
        if provider_type_option_types
          v_prompt = Morpheus::Cli::OptionTypes.prompt(provider_type_option_types, options, @api_client, {})
          payload['storageProvider'].deep_merge!(v_prompt)
        end

        # Default Backup Target
        if options['defaultBackupTarget'] != nil
          payload['storageProvider']['defaultBackupTarget'] = options['defaultBackupTarget']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultBackupTarget', 'fieldLabel' => 'Default Backup Target', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'off'}], options)
          payload['storageProvider']['defaultBackupTarget'] = (v_prompt['defaultBackupTarget'].to_s == 'on') unless v_prompt['defaultBackupTarget'].nil?
        end

        # Archive Snapshots
        if options['copyToStore'] != nil
          payload['storageProvider']['copyToStore'] = options['copyToStore']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'copyToStore', 'fieldLabel' => 'Archive Snapshots', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'on'}], options)
          payload['storageProvider']['copyToStore'] = (v_prompt['copyToStore'].to_s == 'on') unless v_prompt['copyToStore'].nil?
        end

        # Default Deployment Target
        if options['defaultDeploymentTarget'] != nil
          payload['storageProvider']['defaultDeploymentTarget'] = options['defaultDeploymentTarget']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultDeploymentTarget', 'fieldLabel' => 'Default Deployment Target', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'off'}], options)
          payload['storageProvider']['defaultDeploymentTarget'] = (v_prompt['defaultDeploymentTarget'].to_s == 'on') unless v_prompt['defaultDeploymentTarget'].nil?
        end

        # Default Virtual Image Store
        if options['defaultVirtualImageTarget'] != nil
          payload['storageProvider']['defaultVirtualImageTarget'] = options['defaultVirtualImageTarget']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultVirtualImageTarget', 'fieldLabel' => 'Default Virtual Image Store', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'off'}], options)
          payload['storageProvider']['defaultVirtualImageTarget'] = (v_prompt['defaultVirtualImageTarget'].to_s == 'on') unless v_prompt['defaultVirtualImageTarget'].nil?
        end

      end

      
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.create(payload)
        return
      end
      json_response = @storage_providers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        storage_provider = json_response['storageProvider']
        print_green_success "Added storage provider #{storage_provider['name']}"
        get([storage_provider['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[storage-provider] [options]")
      opts.on('--name VALUE', String, "Name for this storage provider") do |val|
        options['name'] = val
      end
      opts.on('--type code', String, "Storage Provider Type Code") do |val|
        options['providerType'] = val
      end
      opts.on('--bucket-name VALUE', String, "Bucket Name") do |val|
        options['bucketName'] = val
      end
      opts.on('--default-backup-target [on|off]', String, "Default Backup Target") do |val|
        options['defaultBackupTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-deployment-target [on|off]', String, "Default Deployment Target") do |val|
        options['defaultDeploymentTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-virtual-image-target [on|off]', String, "Default Virtual Image Store") do |val|
        options['defaultVirtualImageTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--copy-to-store [on|off]', String, "Archive Snapshots") do |val|
        options['copyToStore'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a storage provider." + "\n" +
                    "[storage-provider] is required. This is the id of a storage provider."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      storage_provider = find_storage_provider_by_name_or_id(args[0])
      return 1 if storage_provider.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for storage provider options
        # preserve previous config settings
        payload = {
          'storageProvider' => {
            'config' => storage_provider['config']
          }
        }
        
        # allow arbitrary -O options
        payload['storageProvider'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['storageProvider']['name'] = options['name']
        end

        # Default Backup Target
        if options['defaultBackupTarget'] != nil
          payload['storageProvider']['defaultBackupTarget'] = options['defaultBackupTarget']
        end

        # Archive Snapshots
        if options['copyToStore'] != nil
          payload['storageProvider']['copyToStore'] = options['copyToStore']
        end

        # Default Deployment Target
        if options['defaultDeploymentTarget'] != nil
          payload['storageProvider']['defaultDeploymentTarget'] = options['defaultDeploymentTarget']
        end

        # Default Virtual Image Store
        if options['defaultVirtualImageTarget'] != nil
          payload['storageProvider']['defaultVirtualImageTarget'] = options['defaultVirtualImageTarget']
        end

      end

      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.update(storage_provider["id"], payload)
        return
      end
      json_response = @storage_providers_interface.update(storage_provider["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        storage_provider = json_response['storageProvider']
        print_green_success "Updated storage provider #{storage_provider['name']}"
        get([storage_provider['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[storage-provider]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a storage provider." + "\n" +
                    "[storage-provider] is required. This is the name or id of a storage provider."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [storage-provider]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      storage_provider = find_storage_provider_by_name_or_id(args[0])
      return 1 if storage_provider.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the storage provider: #{storage_provider['name']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.destroy(storage_provider['id'])
        return 0
      end
      json_response = @storage_providers_interface.destroy(storage_provider['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed storage provider #{storage_provider['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


  def get_storage_provider_types()
    [
      {'name' => 'Amazon S3', 'value' => 's3'},
      {'name' => 'Azure', 'value' => 'azure'},
      {'name' => 'CIFS', 'value' => 'cifs'},
      {'name' => 'Local Storage', 'value' => 'local'},
      {'name' => 'NFSv3', 'value' => 'nfs'},
      {'name' => 'Openstack Swift', 'value' => 'openstack'},
      {'name' => 'Rackspace CDN', 'value' => 'rackspace'}
    ]
  end

  def find_storage_provider_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_storage_provider_by_id(val)
    else
      return find_storage_provider_by_name(val)
    end
  end

  def find_storage_provider_by_id(id)
    begin
      json_response = @storage_providers_interface.get(id.to_i)
      return json_response['storageProvider']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Storage Provider not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_storage_provider_by_name(name)
    json_response = @storage_providers_interface.list({name: name.to_s})
    storage_providers = json_response['storageProviders']
    if storage_providers.empty?
      print_red_alert "Storage Provider not found by name #{name}"
      return nil
    elsif storage_providers.size > 1
      print_red_alert "#{storage_providers.size} storage providers found by name #{name}"
      rows = storage_providers.collect do |storage_provider|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return storage_providers[0]
    end
  end

  def format_bucket_name(storage_provider)
    if storage_provider['providerType'] == 'local'
      storage_provider['config'] ? storage_provider['config']['basePath'] : ''
    else
      storage_provider['bucketName']
    end      
  end

  def format_storage_provider_type(storage_provider)
    storage_provider['providerType'].to_s.capitalize
  end

end
