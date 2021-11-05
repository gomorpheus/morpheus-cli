require 'morpheus/cli/cli_command'

class Morpheus::Cli::CertificatesCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'certificates'
  set_command_description "Certificates: View and manage SSL certificates."

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :list_types, :get_type

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @certificates_interface = @api_client.certificates
    @certificate_types_interface = @api_client.certificate_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = "List certificates."
    end
    optparse.parse!(args)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    params.merge!(parse_list_options(options))
    @certificates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificates_interface.dry.list(params)
      return
    end
    json_response = @certificates_interface.list(params)
    render_response(json_response, options, certificate_list_key) do
      certificates = json_response[certificate_list_key]
      print_h1 "Morpheus Certificates", parse_list_subtitles(options), options
      if certificates.empty?
        print cyan,"No certificates found.",reset,"\n"
      else
        list_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Issued To" => lambda {|it|  it['commonName'] },
          "Cert Type" => lambda {|it| it['certType'] },
          "Domain Name" => lambda {|it| it['domainName'] },
        }.upcase_keys!
        print as_pretty_table(certificates, list_columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[certificate]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific certificate.
[certificate] is required. This is the name or id of a certificate.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    certificate = nil
    if id.to_s !~ /\A\d{1,}\Z/
      certificate = find_certificate_by_name_or_id(id)
      return 1, "certificate not found for #{id}" if certificate.nil?
      id = certificate['id']
    end
    @certificates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificates_interface.dry.get(id, params)
      return
    end
    json_response = @certificates_interface.get(id, params)
    certificate = json_response[certificate_object_key]
    render_response(json_response, options, certificate_object_key) do
      print_h1 "Certificate Details", [], options
      print cyan
      show_columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Issued To" => lambda {|it|  it['commonName'] },
        "Cert Type" => lambda {|it| it['certType'] },
        "Domain Name" => lambda {|it| it['domainName'] },
        "Wildcard" => lambda {|it| format_boolean(it['wildcard']) },
      }
      print_description_list(show_columns, certificate, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -t CODE [options]")
      # opts.on('-t', '--type CODE', "Certificate Type code, see `#{command_name} list-types` for available type codes") do |val|
      #   options[:options]['type'] = val
      # end
      build_option_type_options(opts, options, add_certificate_option_types)
      build_option_type_options(opts, options, add_certificate_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new certificate.
[name] is required. This is the name of the new certificate
Configuration options vary by certificate type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({certificate_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({certificate_object_key => parse_passed_options(options)})
      # Type prompt first
      #params['type'] = Morpheus::Cli::OptionTypes.no_prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Blueprint', 'value' => 'blueprint'}, {'name' => 'Workflow', 'value' => 'workflow'}], 'defaultValue' => 'instance', 'required' => true}], options[:options], @api_client, options[:params])['type']
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_certificate_option_types(), options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_certificate_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)

      # lookup type by name or code to validate it exists and to prompt for its optionTypes
      # set certificate.type=code because the api expects it that way.
      if params['type'].to_s.empty?
        raise_command_error "missing required option: --type TYPE", args, optparse
      end
      certificate_type = find_certificate_type_by_name_or_code_id(params['type'])
      if certificate_type.nil?
        print_red_alert "certificate type not found for #{params['type']}"
        return 1, "certificate type not found for #{params['type']}"
      end
      params['type'] = certificate_type['code']
      config_option_types = certificate_type['optionTypes']
      if config_option_types.nil?
        config_option_types = @certificate_types_interface.option_types(certificate_type['id'])['optionTypes']
      end
      if config_option_types.nil?
        print yellow,"No option types found for certificate type: #{certificate_type['name']} (#{certificate_type['code']})", reset, "\n"
      end
      if config_option_types && config_option_types.size > 0
        # optionTypes do not need fieldContext: 'certificate'
        config_option_types.each do |opt|
          if opt['fieldContext'] == 'certificate' || opt['fieldContext'] == 'domain'
            opt['fieldContext'] = nil
          end
        end
        # reject hardcoded optionTypes
        config_option_types = config_option_types.reject {|it| it['fieldName'] == 'name' || it['fieldName'] == 'description' || it['fieldName'] == 'domainName' }
        config_prompt = Morpheus::Cli::OptionTypes.prompt(config_option_types, options[:options], @api_client, options[:params])
        config_prompt.deep_compact!
        params.deep_merge!(config_prompt)
      end
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      payload[certificate_object_key].deep_merge!(params)
    end
    @certificates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificates_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @certificates_interface.create(payload)
    certificate = json_response[certificate_object_key]
    render_response(json_response, options, certificate_object_key) do
      print_green_success "Added certificate #{certificate['name']}"
      return _get(certificate["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[certificate] [options]")
      build_option_type_options(opts, options, update_certificate_option_types)
      build_option_type_options(opts, options, update_certificate_advanced_option_types)
      opts.on(nil, '--no-refresh', "Skip refresh on update.") do
        payload['refresh'] = 'false'
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a certificate.
[certificate] is required. This is the name or id of a certificate.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    certificate = find_certificate_by_name_or_id(args[0])
    return 1 if certificate.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({certificate_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({certificate_object_key => parse_passed_options(options)})
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_certificate_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_certificate_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      payload.deep_merge!({certificate_object_key => params})
      if payload[certificate_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @certificates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificates_interface.dry.update(certificate['id'], payload)
      return
    end
    json_response = @certificates_interface.update(certificate['id'], payload)
    certificate = json_response[certificate_object_key]
    render_response(json_response, options, certificate_object_key) do
      print_green_success "Updated certificate #{certificate['name']}"
      return _get(certificate["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[certificate] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a certificate.
[certificate] is required. This is the name or id of a certificate.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    certificate = find_certificate_by_name_or_id(args[0])
    return 1 if certificate.nil?
    @certificates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificates_interface.dry.destroy(certificate['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the certificate #{certificate['name']}?")
      return 9, "aborted command"
    end
    json_response = @certificates_interface.destroy(certificate['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed certificate #{certificate['name']}"
    end
    return 0, nil
  end


  def list_types(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on('--optionTypes [true|false]', String, "Include optionTypes in the response. Default is false.") do |val|
        params['optionTypes'] = (val.to_s == '' || val.to_s == 'on' || val.to_s == 'true')
      end
      build_standard_list_options(opts, options)
      opts.footer = "List certificate types."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @certificate_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificate_types_interface.dry.list(params)
      return
    end
    json_response = @certificate_types_interface.list(params)
    render_response(json_response, options, certificate_type_list_key) do
      certificate_types = json_response[certificate_type_list_key]
      print_h1 "Morpheus Certificate Types", parse_list_subtitles(options), options
      if certificate_types.empty?
        print cyan,"No certificate types found.",reset,"\n"
      else
        list_columns = certificate_type_column_definitions.upcase_keys!
        print as_pretty_table(certificate_types, list_columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_type(args)
    params = {'optionTypes' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      opts.on('--optionTypes [true|false]', String, "Include optionTypes in the response. Default is true.") do |val|
        params['optionTypes'] = (val.to_s == '' || val.to_s == 'on' || val.to_s == 'true')
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific certificate type.
[type] is required. This is the name or id of a certificate type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get_type(arg, params, options)
    end
  end

  def _get_type(id, params, options)
    certificate_type = nil
    if id.to_s !~ /\A\d{1,}\Z/
      certificate_type = find_certificate_type_by_name_or_code(id)
      return 1, "certificate type not found for name or code '#{id}'" if certificate_type.nil?
      id = certificate_type['id']
    end
    # /api/certificate-types does not return optionTypes by default, use ?optionTypes=true
    @certificate_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @certificate_types_interface.dry.get(id, params)
      return
    end
    json_response = @certificate_types_interface.get(id, params)
    certificate_type = json_response[certificate_type_object_key]
    render_response(json_response, options, certificate_type_object_key) do
      print_h1 "Certificate Type Details", [], options
      print cyan
      show_columns = certificate_type_column_definitions
      print_description_list(show_columns, certificate_type)

      if certificate_type['optionTypes'] && certificate_type['optionTypes'].size > 0
        print_h2 "Option Types"
        opt_columns = [
          # {"ID" => lambda {|it| it['id'] } },
          {"FIELD NAME" => lambda {|it| (it['fieldContext'] && it['fieldContext'] != 'certificate') ? [it['fieldContext'], it['fieldName']].join('.') : it['fieldName']  } },
          {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
          {"TYPE" => lambda {|it| it['type'] } },
          {"DEFAULT" => lambda {|it| it['defaultValue'] } },
          {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
          # {"DESCRIPTION" => lambda {|it| it['description'] }, # do it!
        ]
        print as_pretty_table(certificate_type['optionTypes'], opt_columns)
      else
        # print cyan,"No option types found for this certificate type.","\n",reset
      end

      print reset,"\n"
    end
    return 0, nil
  end

  private

  def format_certificate_type(certificate)
    (certificate['certificateType']['name'] || certificate['certificateType']['code']) rescue certificate['certificateType'].to_s
  end

  def add_certificate_option_types
    [
      {'code' => 'certificate.type', 'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params|
        # @certificate_types_interface.list(max:-1)[certificate_list_key].collect {|it|
        get_available_certificate_types().collect {|it|
          {'name' => it['code'], 'value' => it['id']}
        } }, 'required' => true, 'description' => "Certificate Type code, see `#{command_name} list-types` for available type codes", 'defaultValue' => "internal"},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name of the certificate'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of the certificate'},
      {'fieldName' => 'domainName', 'fieldLabel' => 'Domain Name', 'type' => 'text', 'required' => false, 'description' => 'Domain Name of the certificate'},
      # {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true, 'description' => 'Can be used to disable a certificate'}
    ]
  end

  def add_certificate_advanced_option_types
    []
  end

  def update_certificate_option_types
    list = add_certificate_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  def update_certificate_advanced_option_types
    add_certificate_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def certificate_object_key
    'certificate'
  end

  def certificate_list_key
    'certificates'
  end

  def find_certificate_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_certificate_by_id(val)
    else
      return find_certificate_by_name(val)
    end
  end

  def find_certificate_by_id(id)
    begin
      json_response = @certificates_interface.get(id.to_i)
      return json_response[certificate_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "certificate not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_certificate_by_name(name)
    json_response = @certificates_interface.list({name: name.to_s})
    certificates = json_response[certificate_list_key]
    if certificates.empty?
      print_red_alert "certificate not found by name '#{name}'"
      return nil
    elsif certificates.size > 1
      print_red_alert "#{certificates.size} certificates found by name '#{name}'"
      puts_error as_pretty_table(certificates, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return certificates[0]
    end
  end

  def format_certificate_status(certificate, return_color=cyan)
    out = ""
    status_string = certificate['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{certificate['statusMessage'] ? "#{return_color} - #{certificate['statusMessage']}" : ''}#{return_color}"
    # elsif certificate['enabled'] == false
    #   out << "#{red}DISABLED#{certificate['statusMessage'] ? "#{return_color} - #{certificate['statusMessage']}" : ''}#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'error' || status_string == 'offline'
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{certificate['statusMessage'] ? "#{return_color} - #{certificate['statusMessage']}" : ''}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end


  def certificate_type_column_definitions()
    {
      "ID" => 'id',
      "Code" => 'code',
      "Name" => 'name',
      # "Description" => 'description',
      # "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
    }
  end

  def certificate_type_object_key
    'certificateType'
  end

  def certificate_type_list_key
    'certificateTypes'
  end

  def find_certificate_type_by_name_or_code_id(val, params={})
    if val.to_s =~ /\A\d{1,}\Z/
      return find_certificate_type_by_id(val, params)
    else
      return find_certificate_type_by_name_or_code(val)
    end
  end

  def find_certificate_type_by_id(id, params={})
    begin
      json_response = @certificate_types_interface.get(id.to_i, params)
      return json_response[certificate_type_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "certificate not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_certificate_type_by_name(name, params={})
    json_response = @certificate_types_interface.list(params.merge({name: name.to_s}))
    certificate_types = json_response[certificate_type_list_key]
    if certificate_types.empty?
      print_red_alert "certificate type not found by name '#{name}'"
      return nil
    elsif certificate_types.size > 1
      print_red_alert "#{certificate_types.size} certificate types found by name '#{name}'"
      puts_error as_pretty_table(certificate_types, [:id, :code, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return certificate_types[0]
    end
  end

  def get_available_certificate_types(refresh=false)
    if !@available_certificate_types || refresh
      @available_certificate_types = @certificate_types_interface.list(max:10000)[certificate_type_list_key]
    end
    return @available_certificate_types
  end
  
  def find_certificate_type_by_name_or_code(name)
    records = get_available_certificate_types()
    record = records.find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
    record = record ? record : records.find { |z| z['id'].to_s == name.to_s }
    if record
      return record
    else
      print_red_alert "certificate type not found by '#{name}'"
      return nil
    end
  end

end
