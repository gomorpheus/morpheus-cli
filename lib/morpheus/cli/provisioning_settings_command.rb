require 'morpheus/cli/cli_command'

class Morpheus::Cli::ProvisioningSettingsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'provisioning-settings'

  register_subcommands :get, :update
  
  set_default_subcommand :get

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @provisioning_settings_interface = @api_client.provisioning_settings
    @storage_providers_interface = @api_client.storage_providers
    @key_pairs_interface = @api_client.key_pairs
    @blueprints_interface = @api_client.blueprints
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get provisioning settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    
    begin
      @provisioning_settings_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @provisioning_settings_interface.dry.get()
        return
      end
      json_response = @provisioning_settings_interface.get()
      if options[:json]
        puts as_json(json_response, options, "provisioningSettings")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "provisioningSettings")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['provisioningSettings']], options)
        return 0
      end

      settings = json_response['provisioningSettings']

      print_h1 "Provisioning Settings"
      print cyan

      description_cols = {
        "Allow Cloud Selection" => lambda {|it| format_boolean(it['allowZoneSelection'])},
        "Allow Host Selection" => lambda {|it| format_boolean(it['allowServerSelection'])},
        "Require Environment Selection" => lambda {|it| format_boolean(it['requireEnvironments'])},
        "Show Pricing" => lambda {|it| format_boolean(it['showPricing'])},
        "Hide Datastore Stats On Selection" => lambda {|it| format_boolean(it['hideDatastoreStats'])},
        "Cross-Tenant Naming Policies" => lambda {|it| format_boolean(it['crossTenantNamingPolicies'])},
        "Reuse Naming Sequence Numbers" => lambda {|it| format_boolean(it['reuseSequence'])},
        "Deployment Archive Store" => lambda {|it| it['deployStorageProvider'] ? it['deployStorageProvider']['name'] : nil},
        # Cloud-Init Settings
        "Cloud-Init Username" => lambda {|it| it['cloudInitUsername']},
        "Cloud-Init Password" => lambda {|it| it['cloudInitPassword']},
        "Cloud-Init Key Pair" => lambda {|it| it['cloudInitKeyPair'] ? it['cloudInitKeyPair']['name'] : nil},
        # Windows Settings
        "Windows Adminstrator Password" => lambda {|it| it['windowsPassword']},
        # PXE Boot Settings
        "Default Root Password" => lambda {|it| it['pxeRootPassword']},
        # App Blueprint Settings
        "Default Blueprint Type" => lambda {|it| it['defaultTemplateType'] ? it['defaultTemplateType']['name'].capitalize : 'Morpheus'}
      }
      print_description_list(description_cols, settings)
      print reset "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    params = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      opts.on("--allow-cloud [on|off]", ['on','off'], "Allow cloud selection. Default is on") do |val|
        params['allowZoneSelection'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--allow-host [on|off]", ['on','off'], "Allow host selection. Default is on") do |val|
        params['allowServerSelection'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--require-env [on|off]", ['on','off'], "Require environment selection. Default is on") do |val|
        params['requireEnvironments'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--show-pricing [on|off]", ['on','off'], "Show pricing. Default is on") do |val|
        params['showPricing'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--ds-hide-stats [on|off]", ['on','off'], "Hide datastore stats on selection. Default is on") do |val|
        params['hideDatastoreStats'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--x-tenant-naming [on|off]", ['on','off'], "Cross-tenant naming policies. Default is on") do |val|
        params['crossTenantNamingPolicies'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--reuse-name-seq [on|off]", ['on','off'], "Reuse naming sequence numbers. Default is on") do |val|
        params['reuseSequence'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--deploy-bucket BUCKET", String, "Deployment archive storage provider ID or name") do |val|
        if val == 'null'
          params['deployStorageProvider'] = nil
        else
          options[:deployBucket] = val
        end
      end
      opts.on("--cloud-username STRING", String, "Cloud-init username") do |val|
        params['cloudInitUsername'] = val == 'null' ? nil : val
      end
      opts.on("--cloud-pwd STRING", String, "Cloud-init password") do |val|
        params['cloudInitPassword'] = val == 'null' ? nil : val
      end
      opts.on("--cloud-keypair KEYPAIR", String, "Cloud-init key pair ID or name") do |val|
        if val == 'null'
          params['cloudInitKeyPair'] = nil
        else
          options[:cloudKeyPair] = val
        end
      end
      opts.on("--windows-pwd STRING", String, "Windows administrator password") do |val|
        params['windowsPassword'] = val == 'null' ? nil : val
      end
      opts.on("--pxe-pwd STRING", String, "PXE Boot default root password") do |val|
        params['pxeRootPassword'] = val == 'null' ? nil : val
      end
      opts.on("--blueprint-type TYPE", String, "Default blueprint type ID, name or code") do |val|
        if val == 'null'
          params['defaultTemplateType'] = nil
        else
          options[:blueprintType] = val
        end
      end
      build_common_options(opts, options, [:json, :payload, :dry_run, :quiet, :remote])
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)

      if !payload
        if options[:deployBucket]
          bucket = find_storage_provider(options[:deployBucket])

          if !bucket
            print_red_alert "Storage provider #{options[:deployBucket]} not found"
            exit 1
          end
          params['deployStorageProvider'] = {'id' => bucket['id']}
        end

        if options[:cloudKeyPair]
          key_pair = find_key_pair(options[:cloudKeyPair])

          if !key_pair
            print_red_alert "Key pair #{options[:cloudKeyPair]} not found"
            exit 1
          end
          params['cloudInitKeyPair'] = {'id' => key_pair['id']}
        end

        if options[:blueprintType]
          template_type = find_template_type(options[:blueprintType])

          if !template_type
            print_red_alert "Blueprint type #{options[:blueprintType]} not found"
          end
          params['defaultTemplateType'] = {'code' => template_type['code']}
        end
        payload = {'provisioningSettings' => params}
      end

      @provisioning_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_settings_interface.dry.update(payload)
        return
      end
      json_response = @provisioning_settings_interface.update(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Updated provisioning settings"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error updating provisioning settings: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_storage_provider(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @storage_providers_interface.get(val.to_i)['storageBucket'] : @storage_providers_interface.list({'name' => val})["storageBuckets"].first
  end

  def find_key_pair(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @key_pairs_interface.get(current_account['id'], val.to_i)['keyPair'] : @key_pairs_interface.list(current_account['id'], {'name' => val})["keyPairs"].first
  end

  def find_template_type(val)
    template_types = @provisioning_settings_interface.template_types['templateTypes']
    (val.to_s =~ /\A\d{1,}\Z/) ? template_types.find {|it| it['id'] == val.to_i} : template_types.find {|it| it['name'].casecmp(val) == 0 || it['code'].casecmp(val) == 0}
  end
end
