require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryInstanceTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-instance-types'
  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands({:'update-logo' => :update_logo})
  register_subcommands({:'toggle-featured' => :toggle_featured})

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_instance_types
    @provision_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).provision_types
    @option_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).option_types
    @option_type_lists_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).option_type_lists
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--category VALUE', String, "Filter by category") do |val|
        params['category'] = val
      end
      opts.on('--code VALUE', String, "Filter by code") do |val|
        params['code'] = val
      end
      opts.on('--technology VALUE', String, "Filter by technology") do |val|
        params['provisionTypeCode'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List instance types."
    end
    optparse.parse!(args)
    if args.count > 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @library_instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_instance_types_interface.dry.list(params)
        return
      end
      # do it
      json_response = @library_instance_types_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "instanceTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['instanceTypes'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instanceTypes")
        return 0
      end
      instance_types = json_response['instanceTypes']
      title = "Morpheus Library - Instance Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if instance_types.empty?
        print cyan,"No instance types found.",reset,"\n"
      else
        print_instance_types_table(instance_types, options)
        print_results_pagination(json_response, {:label => "instance type", :n_label => "instance types"})
        # print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)

    begin
      instance_type = find_instance_type_by_name_or_id(id)
      if instance_type.nil?
        return 1
      end
      @library_instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_instance_types_interface.dry.get(instance_type['id'])
        return
      end
      json_response = nil
      if id.to_s =~ /\A\d{1,}\Z/
        json_response = {'instanceType' => instance_type}
      else
        json_response = @library_instance_types_interface.get(instance_type['id'])
        instance_type = json_response['instanceType']
      end
      
      if options[:json]
        puts as_json(json_response, options, "instanceType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instanceType")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['instanceType']], options)
        return 0
      end

      print_h1 "Instance Type Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Code" => lambda {|it| it['code'] },
        "Description" => lambda {|it| it['description'] },
        "Technology" => lambda {|it| format_instance_type_technology(it) },
        "Category" => lambda {|it| it['category'].to_s.capitalize },
        # "Logo" => lambda {|it| it['logo'].to_s },
        "Visiblity" => lambda {|it| it['visibility'].to_s.capitalize },
        "Environment Prefix" => lambda {|it| it['environmentPrefix'] },
        "Enable Settings" => lambda {|it| format_boolean it['hasSettings'] },
        "Enable Scaling" => lambda {|it| format_boolean it['hasAutoScale'] },
        "Supports Deployments" => lambda {|it| format_boolean it['hasDeployment'] },
        "Featured" => lambda {|it| format_boolean it['featured'] },
        "Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        # "Active" => lambda {|it| format_boolean it['active'] },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, instance_type)

      instance_type_option_types = instance_type['optionTypes']
      if instance_type_option_types && instance_type_option_types.size > 0
        print_h2 "Option Types"
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"TYPE" => lambda {|it| it['type'] } },
          {"FIELD NAME" => lambda {|it| it['fieldName'] } },
          {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
          {"DEFAULT" => lambda {|it| it['defaultValue'] } },
          {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
        ]
        print as_pretty_table(instance_type_option_types, columns)
      else
        # print yellow,"No option types found for this layout.","\n",reset
      end

      instance_type_evars = instance_type['environmentVariables']
      if instance_type_evars && instance_type_evars.size > 0
        print_h2 "Environment Variables"
        evar_columns = [
          {"NAME" => lambda {|it| it['name'] } },
          {"VALUE" => lambda {|it| it['defaultValue'] } },
          {"TYPE" => lambda {|it| it['valueType'].to_s.capitalize } },
          {"EXPORT" => lambda {|it| format_boolean it['export'] } },
          {"MASKED" => lambda {|it| format_boolean it['mask'] } },
        ]
        print as_pretty_table(instance_type_evars, evar_columns)
      else
        # print yellow,"No environment variables found for this instance type.","\n",reset
      end

      print_h2 "Layouts"

      instance_type_layouts = instance_type['instanceTypeLayouts']
      
      if instance_type_layouts && instance_type_layouts.size > 0
        # match UI sorting [version desc, name asc]
        # or use something simpler like one of these
        # instance_type_layouts = instance_type_layouts.sort { |a,b| a['name'] <=> b['name'] }
        # instance_type_layouts = instance_type_layouts.sort { |a,b| a['sortOrder'] <=> b['sortOrder'] }
        instance_type_layouts = instance_type_layouts.sort do |a,b|
          a_array = a['instanceVersion'].to_s.split('.').collect {|vn| vn.to_i * -1 }
          while a_array.size < 5
            a_array << 0
          end
          a_array << a['name']
          b_array = b['instanceVersion'].to_s.split('.').collect {|vn| vn.to_i * -1 }
          while b_array.size < 5
            b_array << 0
          end
          b_array << b['name']
          a_array <=> b_array
        end
        layout_columns = [
          {"ID" => lambda {|layout| layout['id'] } },
          {"NAME" => lambda {|layout| layout['name'] } },
          {"VERSION" => lambda {|layout| layout['instanceVersion'] } },
          {"TECHNOLOGY" => lambda {|layout| 
            layout['provisionType'] ? layout['provisionType']['name'] : ''
          } },
          {"DESCRIPTION" => lambda {|layout| layout['description'] } }
        ]
        print as_pretty_table(instance_type_layouts, layout_columns)
      else
        print yellow,"No layouts found for this instance type.","\n",reset
      end

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    logo_file = nil
    option_type_ids = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, add_instance_type_option_types())
      opts.on('--option-types [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          option_type_ids = []
        else
          option_type_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a new instance type."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      #params["name"] = args[0]
      options[:options]["name"] = args[0]
    end
    connect(options)
    begin
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # merge -O options
        payload.deep_merge!({'instanceType' => passed_options}) unless passed_options.empty?
      else
        # merge -O options
        params.deep_merge!(passed_options) unless passed_options.empty?
        # prompt
        v_prompt = Morpheus::Cli::OptionTypes.prompt(add_instance_type_option_types, options[:options], @api_client, options[:params])
        params.deep_merge!(v_prompt)
        if params['logo']
          filename = File.expand_path(params['logo'])
          if !File.exists?(filename)
            print_red_alert "File not found: #{filename}"
            exit 1
          end
          logo_file = File.new(filename, 'rb')
          params.delete('logo')
        end
        params['hasSettings'] = ['on','true','1'].include?(params['hasSettings'].to_s) if params.key?('hasSettings')
        params['hasAutoScale'] = ['on','true','1'].include?(params['hasAutoScale'].to_s) if params.key?('hasAutoScale')
        params['hasDeployment'] = ['on','true','1'].include?(params['hasDeployment'].to_s) if params.key?('hasDeployment')

        # OPTION TYPES
        if params['optionTypes']
          prompt_results = prompt_for_option_types(params, options, @api_client)
          if prompt_results[:success]
            params['optionTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1
          end
        end

        payload = {instanceType: params}
        @library_instance_types_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @library_instance_types_interface.dry.create(payload)
          if logo_file
            print_dry_run @library_instance_types_interface.dry.update_logo(":id", logo_file)
          end
          return
        end
      end

      json_response = @library_instance_types_interface.create(payload)

      if json_response['success']
        if logo_file
          begin
            @library_instance_types_interface.update_logo(json_response['instanceType']['id'], logo_file)
          rescue RestClient::Exception => e
            print_red_alert "Failed to save logo!"
            print_rest_exception(e, options)
          end
        end
      end

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Added Instance Type #{params['name']}"
      _get(json_response['instanceType']['id'], options)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_instance_type_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update an instance type." + "\n" +
                    "[name] is required. This is the name or id of a instance type."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_type = find_instance_type_by_name_or_id(args[0])
      exit 1 if instance_type.nil?
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # merge -O options
        payload.deep_merge!({'instanceType' => passed_options}) unless passed_options.empty?
      else
        # merge -O options
        params.deep_merge!(passed_options) unless passed_options.empty?
        # option_types = update_instance_type_option_types(instance_type)
        # params = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        params['hasSettings'] = ['on','true','1'].include?(params['hasSettings'].to_s) if params.key?('hasSettings')
        params['hasAutoScale'] = ['on','true','1'].include?(params['hasAutoScale'].to_s) if params.key?('hasAutoScale')
        params['hasDeployment'] = ['on','true','1'].include?(params['hasDeployment'].to_s) if params.key?('hasDeployment')
        if params.empty?
          puts optparse
          #option_lines = update_instance_type_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
          #puts "\nAvailable Options:\n#{option_lines}\n\n"
          exit 1
        end
        payload = {'instanceType' => params}
      end
      @library_instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_instance_types_interface.dry.update(instance_type['id'], payload)
        return 0
      end
      
      json_response = @library_instance_types_interface.update(instance_type['id'], payload)
      
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return 0
      end

      print_green_success "Updated Instance Type #{params['name'] || instance_type['name']}"
      _get(json_response['instanceType']['id'], options)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def toggle_featured(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      # opts.on('--featured [on|off]', String, "Featured flag") do |val|
      #   params['featured'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Toggle featured flag for an instance type." + "\n" +
                    "[name] is required. This is the name or id of a instance type."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
    end
    connect(options)
    begin
      instance_type = find_instance_type_by_name_or_id(args[0])
      return 1 if instance_type.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        instance_type_payload = {}
        instance_type_payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload = {'instanceType' => instance_type_payload}
      end
      @library_instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_instance_types_interface.dry.toggle_featured(instance_type['id'], params, payload)
        return 0
      end
      
      json_response = @library_instance_types_interface.toggle_featured(instance_type['id'], params, payload)
      
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return 0
      end
      print_green_success "Updated Instance Type #{params['name'] || instance_type['name']}"
      _get(instance_type['id'], options)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update_logo(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [file]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update the logo for an instance type." + "\n" +
                    "[name] is required. This is the name or id of a instance type." + "\n" +
                    "[file] is required. This is the path of the logo file"
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    layout_id = args[0]
    filename = args[1]
    begin
      instance_type = find_instance_type_by_name_or_id(layout_id)
      exit 1 if instance_type.nil?
      logo_file = nil
      if filename == 'null'
        filename = 'null' # clear it
      else
        filename = File.expand_path(filename)
        if !File.exists?(filename)
          print_red_alert "File not found: #{filename}"
          exit 1
        end
        logo_file = File.new(filename, 'rb')
      end
      @library_instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_instance_types_interface.dry.update_logo(instance_type['id'], logo_file)
        return
      end
      json_response = @library_instance_types_interface.update_logo(instance_type['id'], logo_file)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return 0
      end
      print_green_success "Updated Instance Type #{instance_type['name']} logo"
      _get(instance_type['id'], options)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete an instance type."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      instance_type = find_instance_type_by_name_or_id(args[0])
      exit 1 if instance_type.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the instance type #{instance_type['name']}?", options)
        exit
      end
      @library_instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_instance_types_interface.dry.destroy(instance_type['id'])
        return
      end
      json_response = @library_instance_types_interface.destroy(instance_type['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed Instance Type #{instance_type['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
  
  private

  ## finders are in LibraryHelper

  def add_instance_type_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => true, 'displayOrder' => 2, 'description' => 'Useful shortcode for provisioning naming schemes and export reference.'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 3},
      {'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'select', 'optionSource' => 'categories', 'required' => true, 'displayOrder' => 4},
      {'fieldName' => 'logo', 'fieldLabel' => 'Icon File', 'type' => 'text', 'displayOrder' => 5},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'displayOrder' => 6},
      {'fieldName' => 'environmentPrefix', 'fieldLabel' => 'Environment Prefix', 'type' => 'text', 'displayOrder' => 7, 'description' => 'Used for exportable environment variables when tying instance types together in app contexts. If not specified a name will be generated.'},
      {'fieldName' => 'hasSettings', 'fieldLabel' => 'Enable Settings', 'type' => 'checkbox', 'displayOrder' => 8},
      {'fieldName' => 'hasAutoScale', 'fieldLabel' => 'Enable Scaling (Horizontal)', 'type' => 'checkbox', 'displayOrder' => 9},
      {'fieldName' => 'hasDeployment', 'fieldLabel' => 'Supports Deployments', 'type' => 'checkbox', 'displayOrder' => 10, 'description' => 'Requires a data volume be configured on each version. Files will be copied into this location.'}
    ]
  end

  def update_instance_type_option_types(instance_type=nil)
    opts = add_instance_type_option_types
    opts = opts.reject {|it| ["logo"].include? it['fieldName'] }
    if instance_type
      opts = add_instance_type_option_types
      opts.find {|opt| opt['fieldName'] == 'name'}['defaultValue'] = instance_type['name']
    end
    opts
  end

end
