# require 'yaml'
require 'time'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::MonitoringContactsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :'monitor-contacts'

  register_subcommands :list, :get, :add, :update, :remove
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).monitoring
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :csv, :yaml, :fields, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      # JD: lastUpdated 500ing, contacts don't have that property ? =o  Fix it!

      if options[:dry_run]
        print_dry_run @monitoring_interface.contacts.dry.list(params)
        return
      end

      json_response = @monitoring_interface.contacts.list(params)
      if options[:json]
        puts as_json(json_response, options, "contacts")
        return 0
      end
      if options[:yaml]
        puts as_json(json_response, options, "contacts")
        return 0
      end
      if options[:csv]
        puts records_as_csv(json_response['contacts'], options)
        return 0
      end
      contacts = json_response['contacts']
      title = "Morpheus Monitoring Contacts"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if contacts.empty?
        print cyan,"No contacts found.",reset,"\n"
      else
        print_contacts_table(contacts, options)
        print_results_pagination(json_response, {:label => "contact", :n_label => "contacts"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      opts.on(nil,'--history', "Display History") do |val|
        options[:show_history] = true
      end
      opts.on(nil,'--notifications', "Display Notifications") do |val|
        options[:show_notifications] = true
      end
      build_common_options(opts, options, [:json, :csv, :fields, :dry_run, :remote])
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

  def _get(id, options)

    begin
      contact = find_contact_by_name_or_id(id)
      if options[:dry_run]
        print_dry_run @monitoring_interface.contacts.dry.get(contact['id'])
        return
      end
      json_response = @monitoring_interface.contacts.get(contact['id'])
      contact = json_response['contact']
      
      if options[:json]
        if options[:include_fields]
          json_response = {"contact" => filter_data(json_response["contact"], options[:include_fields]) }
        end
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['contact']], options)
        return 0
      end

      print_h1 "Contact Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Email" => 'emailAddress',
        "Mobile" => 'smsAddress',
        # "Slack Hook" => 'slackHook'
      }
      description_cols["Slack Hook"] = 'slackHook' if !contact['slackHook'].empty?
      puts as_description_list(contact, description_cols)
     
      ## Notifications
      # show notify events here...

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id]")
      opts.on("--name STRING", String, "Contact name") do |val|
        params['name'] = val
      end
      opts.on("--email STRING", String, "Contact email address") do |val|
        params['emailAddress'] = val == 'null' ? nil : val
      end
      opts.on("--mobile STRING", String, "Contact sms addresss") do |val|
        params['smsAddress'] = val == 'null' ? nil : val
      end
      opts.on("--slackHook STRING", String, "Contact slack hook") do |val|
        params['slackHook'] = val == 'null' ? nil : val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    connect(options)

    begin

      if !params["name"]
        print_red_alert "Name is required"
        puts optparse
        exit 1
      end

      payload = {
        'contact' => {}
      }
      payload['contact'].merge!(params)

      if options[:dry_run]
        print_dry_run @monitoring_interface.contacts.dry.create(payload)
        return
      end

      json_response = @monitoring_interface.contacts.create(payload)
      contact = json_response['contact']
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Created contact (#{contact['id']}) #{contact['name']}"
        #_get(contact['id'], {})
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id]")
      opts.on("--name STRING", String, "Contact name") do |val|
        params['name'] = val
      end
      opts.on("--email STRING", String, "Contact email address") do |val|
        params['emailAddress'] = val == 'null' ? nil : val
      end
      opts.on("--mobile STRING", String, "Contact sms addresss") do |val|
        params['smsAddress'] = val == 'null' ? nil : val
      end
      opts.on("--slackHook STRING", String, "Contact slack hook") do |val|
        params['slackHook'] = val == 'null' ? nil : val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      contact = find_contact_by_name_or_id(args[0])

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      payload = {
        'contact' => {id: contact["id"]}
      }
      payload['contact'].merge!(params)

      if options[:dry_run]
        print_dry_run @monitoring_interface.contacts.dry.update(contact["id"], payload)
        return
      end

      json_response = @monitoring_interface.contacts.update(contact["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated contact #{contact['id']}"
        _get(contact['id'], {})
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete contact #{id_list.size == 1 ? 'contact' : 'contacts'} #{anded_list(id_list)}?", options)
      exit 1
    end
    return run_command_for_each_arg(id_list) do |arg|
      _remove(arg, options)
    end
  end

  def _remove(id, options)

    begin
      contact = find_contact_by_name_or_id(id)
      if options[:dry_run]
        print_dry_run @monitoring_interface.contacts.dry.destroy(contact['id'])
        return
      end
      json_response = @monitoring_interface.contacts.destroy(contact['id'])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success json_response["msg"] || "Contact (#{contact['id']}) #{contact['name']} deleted"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def reopen(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to reopen #{id_list.size == 1 ? 'contact' : 'contacts'} #{anded_list(id_list)}?", options)
      exit 1
    end
    return run_command_for_each_arg(id_list) do |arg|
      _reopen(arg, options)
    end
  end

  def _reopen(id, options)

    begin
      contact = find_contact_by_name_or_id(id)
      already_open = contact['status'] == 'open'
      if already_open
        print bold,yellow,"contact #{contact['id']} is already open",reset,"\n"
        return false
      end
      if options[:dry_run]
        print_dry_run @monitoring_interface.contacts.dry.reopen(contact['id'])
        return
      end
      json_response = @monitoring_interface.contacts.reopen(contact['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success json_response["msg"] || "contact #{contact['id']} is now open"
        # _get(contact['id'] {})
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def print_contacts_table(contacts, opts={})
    columns = [
      {"ID" => "id" },
      {"NAME" => "name" },
      {"E-MAIL" => "emailAddress" },
      {"MOBILE" => "smsAddress" },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(contacts, columns, opts)
  end

  
end
