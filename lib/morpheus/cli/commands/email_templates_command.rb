require 'morpheus/cli/cli_command'

class Morpheus::Cli::EmailTemplates
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :execute

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @email_templates_interface = @api_client.email_templates
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")

      build_standard_list_options(opts, options)
      opts.footer = "List email templates."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @email_templates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @email_templates.dry.list(params)
      return
    end

    json_response = @email_templates_interface.list(params)
    templates = json_response['emailTemplates']
    render_response(json_response, options, 'templates') do
      title = "Morpheus Email Templates"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if templates.empty?
        print cyan,"No templates found.",reset,"\n"
      else
        print cyan
        print_templates_table(templates, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if templates.empty?
      return 1, "no templates found"
    else
      return 0, nil
    end
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[emailTemplate]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific email template.
[emailTemplate] is required. This is the name or id of an emailTemplate.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    parse_options(options, params)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    if id.to_s !~ /\A\d{1,}\Z/
      record = find_by_name_or_id('emailTemplate', id)
      if record.nil?
        return 1, "EmailTemplate not found for '#{id}'"
      end
      id = record['id']
    end
    options[:params] = params # parse_options(options, params)
    options.delete(:payload)
    execute_api(@email_templates_interface, :get, [id], options, 'emailTemplate') do |json_response|
      email_template = json_response['emailTemplate']
      print_h1 "EmailTemplate Details", [], options
      print cyan
      columns = email_template_column_definitions
      print_description_list(columns, email_template, options)
      print reset,"\n"
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[name]")
      opts.on("--type [TEXT]", String, "Type") do |val|
        options[:type] = val.to_s
      end
      opts.on( '--template [TEXT]', "Template" ) do |val|
        options[:template] = val.to_s
      end
      opts.on("--enabled [on|off]", ['on','off'], "Template enabled") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end

      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create an email template.\n" +
                    "[name] is required. This is the name of the new template."
    end

    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        payload['emailTemplate'] ||= {}
        if options[:options]
          payload['emailTemplate'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end

        if options[:type]
          payload['emailTemplate']['type'] = options[:type]
        end

        if options[:template]
          payload['emailTemplate']['template'] = options[:template]
        end

        if options[:enabled]
          payload['emailTemplate']['enabled'] = options[:enabled]
        end
      else
        payload = {'emailTemplate' => {}}
       
        # Template Type
        template_type_id = nil
        template_type = options[:type] ? find_template_type_by_name_or_id(options[:type]) : nil

        if template_type
          template_type_id = template_type['id']
        else
          available_template_types = template_types_for_dropdown

          if available_template_types.empty?
            print_red_alert "A template type is required"
            exit 1
          elsif available_template_types.count > 1 && !options[:no_prompt]
            template_type_code = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'templateType', 'type' => 'select', 'fieldLabel' => 'Template Type', 'selectOptions' => template_types_for_dropdown, 'required' => true, 'description' => 'Select Template Type.'}],options[:options],@api_client,{})['type']
          else
            template_type_code = available_template_types.first['code']
          end
          template_type = get_template_types.find { |ct| ct['code'] == template_type_code }
        end

        payload['emailTemplate']['code'] = template_type['value'] 
        payload['emailTemplate']['template'] = Morpheus::Cli::OptionTypes.file_content_prompt({'fieldName' => 'source', 'fieldLabel' => 'File Content', 'type' => 'file-content', 'required' => true}, {'source' => {'source' => 'local'}}, nil, {})['content']
      
        payload['emailTemplate']['enabled'] = Morpheus::Cli::OptionTypes.prompt([ {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true}])['enabled']

      end
      @email_templates_interface.setopts(options)
      if options[:dry_run]
         print_dry_run @email_templates_interface.dry.create(payload)
         return
      end
      json_response = @email_templates_interface.create(payload)
      if options[:json]
         print JSON.pretty_generate(json_response)
         print "\n"
      elsif json_response['success']
         get_args = [json_response["emailTemplate"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
         get(get_args)
      else
         print_rest_errors(json_response, options)
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[emailTemplate] --template")
      opts.on("--template TEMPLATE", String, "Updates Email Template") do |val|
        options[:template] = val.to_s
      end
      opts.on("--enabled ENABLED", String "Updates Template Enabled") do |val|
        options[:enabled] = val.to_s 'on'
      end

      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update an Email Template.\n" +
                    "[emailTemplate] is required. This is the name or id of an existing email template."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      payload = nil
      email_template = nil

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['emailTemplate'] ||= {}
          payload['emailTemplate'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end

        if !payload['emailTemplate'].empty?
          email_template = find_by_name_or_id('emailTemplate', payload['emailTemplate']['id'] || payload['emailTemplate']['name'])
        end
      else
        email_template = find_by_name_or_id('emailTemplate', args[0])
        template_payload = {}
        template_payload['template'] = options[:template]

        payload = {"emailTemplate" => template_payload}
      end

      if !email_template
        print_red_alert "No templates available for update"
        exit 1
      end

      if payload.empty?
        print_green_success "Nothing to update"
        exit 1
      end

      @email_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @email_templates_interface.dry.update(email_template['id'], payload)
        return
      end
      json_response = @email_templates_interface.update(email_template['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        get_args = [json_response["emailTemplate"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      else
        print_rest_errors(json_response, options)
      end
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[emailTemplate]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete an email template.\n" +
                    "[emailTemplate] is required. This is the id of an existing email template.\n" +
                    "Note: You cannot remove System Templates, only those that you own/created."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      email_template = find_by_name_or_id('emailTemplate', args[0])

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the email template '#{email_template['name']}'?", options)
        return 9, "aborted command"
      end
      @email_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @email_templates_interface.dry.destroy(email_template['id'], query_params)
        return
      end
      json_response = @email_templates_interface.destroy(email_template['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        msg = "Email Template #{email_template['name']} is being removed..."
        if json_response['msg'] != nil && json_response['msg'] != ''
          msg = json_response['msg']
        end
        print_green_success msg
        
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end



  def print_templates_table(templates, opts={})
    columns = [
      {"ID" => lambda {|it| it['id'] } },
      {"NAME" => lambda {|it| it['name'] } },
      {"ACCOUNT" => lambda {|it| it['account']['name'] || 'System'} },
      {"ENABLED" => lambda {|it| it['enabled'] } }

      # {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(templates, columns, opts)
  end

  def email_template_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Account" => lambda {|it| it['account']['name'] || 'System' },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Template" => lambda {|it| it['template'] rescue '' }
    }
  end

  def template_types_for_dropdown
    get_template_types.collect {|it| {'name' => it['name'], 'code' => it['value'], 'value' => it['value']} }
  end

  def get_template_types(refresh=false)
    if !@template_types || refresh
      @template_types = @email_templates_interface.template_types()['types']
    end
    @template_types
  end
end