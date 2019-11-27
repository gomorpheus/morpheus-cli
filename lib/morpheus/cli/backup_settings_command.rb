require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupSettingsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'backup-settings'
  set_command_hidden
  register_subcommands :get, :update
  set_default_subcommand :get

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backup_settings_interface = @api_client.backup_settings
    @options_interface = @api_client.options
    @storage_providers = @api_client.storage_providers
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get backup settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    
    begin
      @backup_settings_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @backup_settings_interface.dry.get(options)
        return
      end
      json_response = @backup_settings_interface.get(options)
      if options[:json]
        puts as_json(json_response, options, "backupSettings")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "backupSettings")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['backupSettings']], options)
        return 0
      end

      backup_settings = json_response['backupSettings']

      print_h1 "Backup Settings"
      print cyan
      description_cols = {
        "Scheduled Backups" => lambda {|it| format_boolean(it['backupsEnabled']) },
        "Create Backups" => lambda {|it| format_boolean(it['createBackups']) },
        "Backup Appliance" => lambda {|it| format_boolean(it['backupAppliance']) },
        "Default Backup Bucket" => lambda {|it| it['defaultStorageBucket'] ? it['defaultStorageBucket']['name'] : '' },
        "Default Backup Schedule" => lambda {|it| it['defaultSchedule'] ? it['defaultSchedule']['name'] : ''},
        "Backup Retention Count" => lambda {|it| it['retentionCount'] }
      }
      print_description_list(description_cols, backup_settings)
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
      opts.on('-a', '--active [on|off]', String, "Can be used to enable / disable the scheduled backups. Default is on") do |val|
        params['backupsEnabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--create-backups [on|off]", String, "Can be used to enable / disable create backups. Default is on") do |val|
        params['createBackups'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--backup-appliance [on|off]", ['on','off'], "Can be use to enable / disable backup appliance. Default is on") do |val|
        params['backupAppliance'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("-b", "--bucket BUCKET", String, "Default storage bucket name or ID") do |val|
        options[:storageBucket] = val
      end
      opts.on("--clear-bucket", "Use this flag to clear default backup bucket") do |val|
        params['clearDefaultStorageBucket'] = true
      end
      opts.on("-u", "--update-existing", "Use this flag to update existing backups with new settings") do |val|
        params['updateExisting'] = true
      end
      opts.on("-s", "--backup-schedule ID", String, "Backup schedule type ID") do |val|
        options[:backupSchedule] = val
      end
      opts.on("--clear-schedule", "Use this flag to clear default backup schedule") do |val|
        params['clearDefaultSchedule'] = true
      end
      opts.on("-R", "--retention NUMBER", Integer, "Maximum number of successful backups to retain") do |val|
        params['retentionCount'] = val.to_i
      end
      build_common_options(opts, options, [:json, :payload, :dry_run, :quiet, :remote])
      opts.footer = "Update your backup settings."
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
        payload = {'backupSettings' => params}

        if !options[:backupSchedule].nil?
          backup_schedule = @options_interface.options_for_source('executeSchedules', {})['data'].find do |it|
            it['name'] == options[:backupSchedule] || it['value'] == options[:backupSchedule].to_i
          end

          if backup_schedule.nil?
            print_red_alert "Backup schedule type not found for #{options[:backupSchedule]}"
            return 1
          end
          payload['backupSettings']['defaultSchedule'] = {'id' => backup_schedule['value'].to_i}
        end

        if !options[:storageBucket].nil?
          storage_bucket = find_storage_bucket_by_name_or_id(options[:storageBucket])
          if storage_bucket.nil?
            print_red_alert "Storage bucket not found for #{options[:storageBucket]}"
            return 1
          end
          payload['backupSettings']['defaultStorageBucket'] = {'id' => storage_bucket['id']}
        end
      end

      if payload['backupSettings'].empty?
        print_green_success "Nothing to update"
        exit 1
      end

      @backup_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @backup_settings_interface.dry.update(payload)
        return
      end
      json_response = @backup_settings_interface.update(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Updated log settings"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error updating log settings: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_storage_bucket_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @storage_providers.get(val)['storageBucket'] : @storage_providers.list({'name' => val})['storageBuckets'].first
  end
end
