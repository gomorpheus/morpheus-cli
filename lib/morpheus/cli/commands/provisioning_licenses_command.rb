require 'morpheus/cli/cli_command'

class Morpheus::Cli::ProvisioningLicensesCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'provisioning-licenses'
  register_subcommands :list, :get, :add, :update, :remove, :reservations, :'list-types'

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @provisioning_licenses_interface = @api_client.provisioning_licenses
    @provisioning_license_types_interface = @api_client.provisioning_license_types
    @virtual_images_interface = @api_client.virtual_images
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
      build_standard_list_options(opts, options)
      opts.footer = "List licenses."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @provisioning_licenses_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_licenses_interface.dry.list(params)
        return 0
      end
      json_response = @provisioning_licenses_interface.list(params)
      render_result = render_with_format(json_response, options, 'licenses')
      return 0 if render_result
      licenses = json_response['licenses']

      title = "Morpheus Licenses"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if licenses.empty?
        print cyan,"No licenses found.",reset,"\n"
      else
        columns = [
          {"ID" => lambda {|license| license['id'] } },
          {"NAME" => lambda {|license| license['name'] } },
          {"LICENSE TYPE" => lambda {|license| license['licenseType']['name'] rescue license['licenseType'] } },
          {"VERSION" => lambda {|license| license['licenseVersion'] } },
          {"COPIES" => lambda {|license| 
            "#{license['reservationCount']}/#{license['copies']}"
          } },
          {"VIRTUAL IMAGES" => lambda {|it| it['virtualImages'] ? it['virtualImages'].collect {|v| v['name']}.join(', ') : '' } },
          {"TENANTS" => lambda {|it| it['tenants'] ? it['tenants'].collect {|acnt| acnt['name']}.join(', ') : '' } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(licenses, columns, options)
        print_results_pagination(json_response)
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[license]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a license.\n[license] is required. License ID or name"
    end
    optparse.parse!(args)

    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end

    connect(options)
    
    begin
      @provisioning_licenses_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @provisioning_licenses_interface.dry.get(args[0], params)
        else
          print_dry_run @provisioning_licenses_interface.dry.list({name: args[0].to_s})
        end
        return 0
      end
      license = find_license_by_name_or_id(args[0])
      return 1 if license.nil?
      # skip reload if already fetched via get(id)
      json_response = {'license' => license}
      if args[0].to_s != license['id'].to_s
        json_response = @provisioning_licenses_interface.get(license['id'], params)
        license = json_response['license']
      end
      render_result = render_with_format(json_response, options, 'license')
      return 0 if render_result

      
      print_h1 "License Details"
      print cyan
      columns = [
        {"ID" => lambda {|license| license['id'] } },
        {"Name" => lambda {|license| license['name'] } },
        {"License Type" => lambda {|license| license['licenseType']['name'] rescue license['licenseType'] } },
        {"License Key" => lambda {|license| license['licenseKey'] } },
        {"Org Name" => lambda {|license| license['orgName'] } },
        {"Full Name" => lambda {|license| license['fullName'] } },
        {"Version" => lambda {|license| license['licenseVersion'] } },
        {"Description" => lambda {|license| license['description'] } },
        {"Copies" => lambda {|license| 
          "#{license['reservationCount']}/#{license['copies']}"
        } },
        {"Description" => lambda {|license| license['description'] } },
        {"Virtual Images" => lambda {|it| it['virtualImages'] ? it['virtualImages'].collect {|v| v['name']}.join(', ') : '' } },
        {"Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|acnt| acnt['name']}.join(', ') : '' } },
      ]
      print_description_list(columns, license, options)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on( '-t', '--type TYPE', "License Type Code eg. win" ) do |val|
        options[:options]['licenseType'] ||= val
      end
      opts.add_hidden_option('--licenseType')
      build_option_type_options(opts, options, add_license_option_types)
      build_standard_add_options(opts, options)
      opts.footer = "Create license."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options]['name'] ||= args[0]
    end
    connect(options)
    begin
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'license' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'license' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'license' => passed_options}) unless passed_options.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt(add_license_option_types, options[:options], @api_client)
        params.deep_merge!(v_prompt)
        payload.deep_merge!({'license' => params}) unless params.empty?
      end

      @provisioning_licenses_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_licenses_interface.dry.create(payload)
        return
      end
      json_response = @provisioning_licenses_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['license']  ? json_response['license']['name'] : ''
        print_green_success "License #{display_name} added"
        get([json_response['license']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[license] [options]")
      build_option_type_options(opts, options, update_license_option_types)
      build_standard_update_options(opts, options)
      opts.footer = "Update license.\n[license] is required. License ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin

      license = find_license_by_name_or_id(args[0])
      return 1 if license.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'license' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'license' => {
          }
        }
        # allow arbitrary -O options
        # virtual_images = passed_options.delete('virtualImages')
        # tenants = passed_options.delete('tenants')
        payload.deep_merge!({'license' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_license_option_types, options[:options], @api_client, options[:params])
        v_prompt = Morpheus::Cli::OptionTypes.prompt(update_license_option_types, options[:options].merge(:no_prompt => true), @api_client)
        params.deep_merge!(v_prompt)
        
        # if !virtual_images.empty?
        #   params['virtualImages'] = virtual_images # split(",") and lookup ?
        # end
        
        payload.deep_merge!({'license' => params}) unless params.empty?

        if payload.empty? || payload['license'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end
      @provisioning_licenses_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_licenses_interface.dry.update(license['id'], payload)
        return
      end
      json_response = @provisioning_licenses_interface.update(license['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['license'] ? json_response['license']['name'] : ''
        print_green_success "License #{display_name} updated"
        get([json_response['license']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_remove_options(opts, options)
      opts.footer = "Delete license.\n[license] is required. License ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      license = find_license_by_name_or_id(args[0])
      return 1 if license.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the license #{license['name']}?")
        return 9, "aborted command"
      end
      @provisioning_licenses_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_licenses_interface.dry.destroy(license['id'])
        return
      end
      json_response = @provisioning_licenses_interface.destroy(license['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "License #{license['name']} removed"
        # list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def reservations(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_list_options(opts, options)
      opts.footer = "List reservations for a license.\n[license] is required. License ID or name"
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      license = find_license_by_name_or_id(args[0])
      return 1 if license.nil?
      params.merge!(parse_list_options(options))
      @provisioning_licenses_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_licenses_interface.dry.reservations(license['id'], params)
        return 0
      end
      json_response = @provisioning_licenses_interface.reservations(license['id'], params)
      render_result = render_with_format(json_response, options, 'reservations')
      return 0 if render_result
      reservations = json_response['reservations']
      
      title = "License Reservations: [#{license['id']}] #{license['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if reservations.empty?
        print cyan,"No reservations found.",reset,"\n"
      else
        columns = [
          #{"ID" => lambda {|it| it['id'] } },
          {"RESOURCE ID" => lambda {|it| it['resourceId'] } },
          {"RESOURCE TYPE" => lambda {|it| it['resourceType'] } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(reservations, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_types(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_list_options(opts, options)
      opts.footer = "List license types."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @provisioning_license_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @provisioning_license_types_interface.dry.list(params)
        return 0
      end
      json_response = @provisioning_license_types_interface.list(params)
      render_result = render_with_format(json_response, options, 'licenseTypes')
      return 0 if render_result
      license_types = json_response['licenseTypes']

      title = "Morpheus License Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if license_types.empty?
        print cyan,"No license types found.",reset,"\n"
      else
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"CODE" => lambda {|it| it['code'] } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(license_types, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_license_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_license_by_id(val)
    else
      return find_license_by_name(val)
    end
  end

  def find_license_by_id(id)
    raise "#{self.class} has not defined @provisioning_licenses_interface" if @provisioning_licenses_interface.nil?
    begin
      json_response = @provisioning_licenses_interface.get(id)
      return json_response['license']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "License not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_license_by_name(name)
    raise "#{self.class} has not defined @provisioning_licenses_interface" if @provisioning_licenses_interface.nil?
    licenses = @provisioning_licenses_interface.list({name: name.to_s})['licenses']
    if licenses.empty?
      print_red_alert "License not found by name #{name}"
      return nil
    elsif licenses.size > 1
      print_red_alert "#{licenses.size} Licenses found by name #{name}"
      print as_pretty_table(licenses, [:id,:name], {color:red})
      print reset,"\n"
      return nil
    else
      return licenses[0]
    end
  end

  # def get_license_types_dropdown()
  #   [{"name" => "Windows", "value" => "win"}]
  # end

  def get_license_types_dropdown()
    @provisioning_license_types_interface.list({max:10000})['licenseTypes'].collect { |it|
      {"name" => it["name"], "value" => it["code"]}
    }
  end

  def get_virtual_images_dropdown()
    @virtual_images_interface.list({max:10000})['virtualImages'].collect { |it|
      {"name" => it["name"], "value" => it["id"]}
    }
  end

  def add_license_option_types
    [
      {'fieldName' => 'licenseType', 'fieldLabel' => 'License Type', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        # @options_interface.options_for_source("licenseTypes", {})['data']
        get_license_types_dropdown()
      }, 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true, 'displayOrder' => 3},
      {'fieldName' => 'orgName', 'fieldLabel' => 'Org Name', 'type' => 'text', 'description' => "The Organization Name (if applicable) related to the license key", 'displayOrder' => 4},
      {'fieldName' => 'fullName', 'fieldLabel' => 'Full Name', 'type' => 'text', 'description' => "The Full Name (if applicable) related to the license key", 'displayOrder' => 5},
      {'fieldName' => 'licenseVersion', 'fieldLabel' => 'Version', 'type' => 'text', 'displayOrder' => 6},
      {'fieldName' => 'copies', 'fieldLabel' => 'Copies', 'type' => 'number', 'required' => true, 'defaultValue' => 1, 'displayOrder' => 7},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 8},
      {'fieldName' => 'virtualImages', 'fieldLabel' => 'Virtual Images', 'type' => 'multiSelect', 'optionSource' => lambda { |api_client, api_params| 
        # @options_interface.options_for_source("virtualImages", {})['data']
        get_virtual_images_dropdown()
      }, 'displayOrder' => 9},
      {'fieldName' => 'tenants', 'fieldLabel' => 'Tenants', 'type' => 'multiSelect', 'optionSource' => lambda { |api_client, api_params| 
        @options_interface.options_for_source("allTenants", {})['data']
      }, 'displayOrder' => 10},
    ]
  end

  def update_license_option_types
    list = add_license_option_types()
    list = list.reject {|it| ["licenseType", "licenseKey", "orgName", "fullName"].include? it['fieldName'] }
    list.each {|it| it.delete('required') }
    list.each {|it| it.delete('defaultValue') }
    list
  end

end
