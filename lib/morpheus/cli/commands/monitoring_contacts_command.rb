require 'morpheus/cli/cli_command'

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
    @monitoring_interface = @api_client.monitoring
    @monitoring_contacts_interface = @api_client.monitoring.contacts
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :csv, :yaml, :fields, :json, :dry_run, :remote])
      opts.footer = "List monitoring contacts."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      # JD: lastUpdated 500ing, contacts don't have that property ? =o  Fix it!
      @monitoring_contacts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_contacts_interface.dry.list(params)
        return
      end

      json_response = @monitoring_contacts_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "contacts")
        return 0
      elsif options[:yaml]
        puts as_json(json_response, options, "contacts")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['contacts'], options)
        return 0
      end
      contacts = json_response['contacts']
      title = "Morpheus Monitoring Contacts"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[contact]")
      opts.on(nil,'--history', "Display History") do |val|
        options[:show_history] = true
      end
      opts.on(nil,'--notifications', "Display Notifications") do |val|
        options[:show_notifications] = true
      end
      build_common_options(opts, options, [:json, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a monitoring contact." + "\n" +
                    "[contact] is required. This is the name or ID of the contact. Supports 1-N [contact] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
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
      @monitoring_contacts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_contacts_interface.dry.get(contact['id'])
        return
      end
      # save a request
      # json_response = @monitoring_contacts_interface.get(contact['id'])
      # contact = json_response['contact']
      json_response = {'contact' => contact}
      
      if options[:json]
        puts as_json(json_response, options, "contact")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "contact")
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
        "Slack Hook" => 'slackHook'
      }
      description_cols.delete("Slack Hook") if contact['slackHook'].to_s.empty?
      puts as_description_list(contact, description_cols)
     
      ## Notifications
      # show notify events here...

      print reset
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a monitoring contact." + "\n" +
                    "[name] is required. This is the name of the new contact."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      params['name'] = args[0]
    end
    begin
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      if params['name'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'The name of this contact.'}], options[:options])
        params['name'] = v_prompt['name']
      end
      if params['emailAddress'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'emailAddress', 'type' => 'text', 'fieldLabel' => 'Email', 'required' => false, 'description' => 'Contact email address.'}], options[:options])
        params['emailAddress'] = v_prompt['emailAddress'] unless v_prompt['emailAddress'].to_s.empty?
      end
      if params['smsAddress'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'smsAddress', 'type' => 'text', 'fieldLabel' => 'Mobile', 'required' => false, 'description' => 'Contact sms address, or phone number.'}], options[:options])
        params['smsAddress'] = v_prompt['smsAddress'] unless v_prompt['smsAddress'].to_s.empty?
      end
      # if params['slackHook'].nil?
      #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'slackHook', 'type' => 'text', 'fieldLabel' => 'Slack Hook', 'required' => false, 'description' => 'Contact slack hook.'}], options[:options])
      #   params['slackHook'] = v_prompt['slackHook'] unless v_prompt['slackHook'].to_s.empty?
      # end
      payload = {
        'contact' => {}
      }
      payload['contact'].merge!(params)
      @monitoring_contacts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_contacts_interface.dry.create(payload)
        return
      end

      json_response = @monitoring_contacts_interface.create(payload)
      contact = json_response['contact']
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Created contact (#{contact['id']}) #{contact['name']}"
        #_get(contact['id'], options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[contact]")
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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update a monitoring contact." + "\n" +
                    "[contact] is required. This is the name or ID of the contact."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)

    begin
      contact = find_contact_by_name_or_id(args[0])

      if params.empty?
        print_red_alert "Specify at least one option to update"
        puts optparse
        exit 1
      end

      payload = {
        'contact' => {id: contact["id"]}
      }
      payload['contact'].merge!(params)
      @monitoring_contacts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_contacts_interface.dry.update(contact["id"], payload)
        return
      end

      json_response = @monitoring_contacts_interface.update(contact["id"], payload)
      contact = json_response['contact']
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated contact (#{contact['id']}) #{contact['name']}"
        _get(contact['id'], options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[contact]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Delete a monitoring contact." + "\n" +
                    "[contact] is required. This is the name or ID of the contact. Supports 1-N [contact] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete #{id_list.size == 1 ? 'contact' : 'contacts'} #{anded_list(id_list)}?", options)
      exit 1
    end
    return run_command_for_each_arg(id_list) do |arg|
      _remove(arg, options)
    end
  end

  def _remove(id, options)

    begin
      contact = find_contact_by_name_or_id(id)
      @monitoring_contacts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @monitoring_contacts_interface.dry.destroy(contact['id'])
        return
      end
      json_response = @monitoring_contacts_interface.destroy(contact['id'])
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
