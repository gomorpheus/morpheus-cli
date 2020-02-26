require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryOptionTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-option-types'
  register_subcommands :list, :get, :add, :update, :remove

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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_list_options(opts, options)
      opts.footer = "List option types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @option_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.list(params)
        return
      end

      json_response = @option_types_interface.list(params)

      render_result = render_with_format(json_response, options, 'optionTypes')
      return 0 if render_result

      option_types = json_response['optionTypes']
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Option Types", subtitles
      if option_types.empty?
        print cyan,"No option types found.",reset,"\n"
      else
        rows = option_types.collect do |option_type|
          {
            id: option_type['id'],
            name: option_type['name'],
            type: option_type['type'],
            fieldLabel: option_type['fieldLabel'],
            fieldName: option_type['fieldName'],
            default: option_type['defaultValue'],
            required: option_type['required'] ? 'yes' : 'no'
          }
        end
        print cyan
        print as_pretty_table(rows, [
          :id,
          :name,
          :type,
          {:fieldLabel => {:display_name => "Field Label"} },
          {:fieldName => {:display_name => "Field Name"} },
          :default,
          :required
        ], options)
        print reset
        print_results_pagination(json_response)
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
      opts.banner = subcommand_usage("[name]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about an option type.\n" + 
                    "[name] is required. This is the name or id of an option type. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    begin
      @option_types_interface.setopts(options)
      if options[:dry_run]
        if id.to_s =~ /\A\d{1,}\Z/
          print_dry_run @option_types_interface.dry.get(id.to_i)
        else
          print_dry_run @option_types_interface.dry.list({name: id})
        end
        return
      end
      option_type = find_option_type_by_name_or_id(id)
      return 1 if option_type.nil?
      json_response = {'optionType' => option_type}

      render_result = render_with_format(json_response, options, 'optionType')
      return 0 if render_result

      print_h1 "Option Type Details"
      print cyan
      print_description_list({
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Field Label" => 'fieldLabel',
        # "Field Context" => 'fieldContext',
        # "Field Name" => 'fieldName',
        "Full Field Name" => lambda {|it| [it['fieldContext'], it['fieldName']].select {|it| !it.to_s.empty? }.join('.') },
        "Type" => lambda {|it| it['type'].to_s.capitalize },
        "Placeholder" => 'placeHolder',
        "Default Value" => 'defaultValue',
        "Required" => lambda {|it| format_boolean(it['required']) },
      }, option_type)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_option_type_options(opts, options, new_option_type_option_types)
      build_standard_add_options(opts, options)
      opts.footer = "Create a new option type."
    end
    optparse.parse!(args)
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['optionType'] ||= {}
          payload['optionType'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        params = Morpheus::Cli::OptionTypes.prompt(new_option_type_option_types, options[:options], @api_client, options[:params])
        if params.key?('required')
          params['required'] = ['on','true'].include?(params['required'].to_s)
        end
        option_type_payload = params
        payload = {optionType: option_type_payload}
      end
      @option_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.create(payload)
        return
      end
      json_response = @option_types_interface.create(payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      option_type = json_response['optionType']
      print_green_success "Added Option Type #{option_type['name']}"
      #list([])
      get([option_type['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_option_type_option_types)
      build_standard_update_options(opts, options)
      opts.footer = "Update an option type.\n" +
                    "[name] is required. This is the name or id of an option type."
    end
    optparse.parse!(args)
    connect(options)
    begin
      option_type = find_option_type_by_name_or_id(args[0])
      exit 1 if option_type.nil?

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['optionType'] ||= {}
          payload['optionType'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        #params = options[:options] || {}
        params = Morpheus::Cli::OptionTypes.no_prompt(update_option_type_option_types, options[:options], @api_client, options[:params])
        if params.empty?
          print_red_alert "Specify at least one option to update"
          puts optparse
          exit 1
        end
        if params.key?('required')
          params['required'] = ['on','true'].include?(params['required'].to_s)
        end
        option_type_payload = params
        payload = {optionType: option_type_payload}
      end
      @option_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.update(option_type['id'], payload)
        return
      end
      json_response = @option_types_interface.update(option_type['id'], payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      print_green_success "Updated Option Type #{option_type_payload['name']}"
      #list([])
      get([option_type['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_remove_options(opts, options)
      opts.footer = "Delete an option type.\n" +
                    "[name] is required. This is the name or id of an option type."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      option_type = find_option_type_by_name_or_id(args[0])
      exit 1 if option_type.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the option type #{option_type['name']}?", options)
        exit
      end
      @option_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.destroy(option_type['id'])
        return
      end
      json_response = @option_types_interface.destroy(option_type['id'])

      render_result = render_with_format(json_response, options)
      return 0 if render_result

      print_green_success "Removed Option Type #{option_type['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private

  def find_instance_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_instance_type_by_id(val)
    else
      return find_instance_type_by_name(val)
    end
  end

  def find_instance_type_by_id(id)
    begin
      json_response = @library_instance_types_interface.get(id.to_i)
      return json_response['instanceType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance Type not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_instance_type_by_name(name)
    json_response = @library_instance_types_interface.list({name: name.to_s})
    instance_types = json_response['instanceTypes']
    if instance_types.empty?
      print_red_alert "Instance Type not found by name #{name}"
      return nil
    elsif instance_types.size > 1
      print_red_alert "#{instance_types.size} instance types found by name #{name}"
      print_instance_types_table(instance_types, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return instance_types[0]
    end
  end

  def print_instance_types_table(instance_types, opts={})
    columns = [
      {"ID" => lambda {|instance_type| instance_type['id'] } },
      {"NAME" => lambda {|instance_type| instance_type['name'] } },
      {"CODE" => lambda {|instance_type| instance_type['code'] } },
      {"TECHNOLOGY" => lambda {|instance_type| format_instance_type_technology(instance_type) } },
      {"CATEGORY" => lambda {|instance_type| instance_type['category'].to_s.capitalize } },
      {"FEATURED" => lambda {|instance_type| format_boolean instance_type['featured'] } },
      {"OWNER" => lambda {|instance_type| instance_type['account'] ? instance_type['account']['name'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(instance_types, columns, opts)
  end

  def format_instance_type_technology(instance_type)
    if instance_type
      instance_type['provisionTypeCode'].to_s.capitalize
    else
      ""
    end
  end

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

  def load_balance_protocols
    [
      {'name' => 'None', 'value' => ''},
      {'name' => 'HTTP', 'value' => 'HTTP'},
      {'name' => 'HTTPS', 'value' => 'HTTPS'},
      {'name' => 'TCP', 'value' => 'TCP'}
    ]
  end

  # finders are in LibraryHelper

  # lol
  def new_option_type_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
      {'fieldName' => 'fieldName', 'fieldLabel' => 'Field Name', 'type' => 'text', 'required' => true, 'description' => 'This is the input fieldName property that the value gets assigned to.', 'displayOrder' => 3},
      {'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Text', 'value' => 'text'}, {'name' => 'Password', 'value' => 'password'}, {'name' => 'Number', 'value' => 'number'}, {'name' => 'Checkbox', 'value' => 'checkbox'}, {'name' => 'Select', 'value' => 'select'}, {'name' => 'Hidden', 'value' => 'hidden'}], 'defaultValue' => 'text', 'required' => true, 'displayOrder' => 4},
      {'fieldName' => 'fieldLabel', 'fieldLabel' => 'Field Label', 'type' => 'text', 'required' => true, 'description' => 'This is the input label that shows typically to the left of a custom option.', 'displayOrder' => 5},
      {'fieldName' => 'placeHolder', 'fieldLabel' => 'Placeholder', 'type' => 'text', 'displayOrder' => 6},
      {'fieldName' => 'defaultValue', 'fieldLabel' => 'Default Value', 'type' => 'text', 'displayOrder' => 7},
      {'fieldName' => 'required', 'fieldLabel' => 'Required', 'type' => 'checkbox', 'defaultValue' => 'off', 'displayOrder' => 8},
    ]
  end

  def update_option_type_option_types
    list = new_option_type_option_types
    list.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
      it.delete('skipSingleOption')
    }
    list
  end

end
