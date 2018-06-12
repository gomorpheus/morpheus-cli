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
      build_common_options(opts, options, [:list, :query, :dry_run, :json, :remote])
      opts.footer = "List option types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.list(params)
        return
      end

      json_response = @option_types_interface.list(params)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

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
        tp rows, [
          :id,
          :name,
          :type,
          {:fieldLabel => {:display_name => "Field Label"} },
          {:fieldName => {:display_name => "Field Name"} },
          :default,
          :required
        ]
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
      if options[:dry_run]
        if id.to_s =~ /\A\d{1,}\Z/
          print_dry_run @option_types_interface.dry.get(id.to_i)
        else
          print_dry_run @option_types_interface.dry.list({name: id})
        end
        return
      end
      option_type = find_option_type_by_name_or_id(id)
      exit 1 if option_type.nil?

      if options[:json]
        puts as_json(json_response, options, "optionType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "optionType")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['optionType']], options)
        return 0
      end

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
        "Default Value" => 'defaultValue'
      }, option_type)
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    # JD: this is annoying because our option_types (for prompting and help)
    # are the same type of object being managed here.., options options options
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_option_type_options(opts, options, new_option_type_option_types)
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = Morpheus::Cli::OptionTypes.prompt(new_option_type_option_types, options[:options], @api_client, options[:params])
      if params.key?('required')
        params['required'] = ['on','true'].include?(params['required'].to_s)
      end
      option_type_payload = params
      payload = {optionType: option_type_payload}
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.create(payload)
        return
      end
      json_response = @option_types_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      option_type = json_response['optionType']
      print_green_success "Added Option Type #{option_type['name']}"
      #list([])
      get([option_type['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    # JD: this is annoying because our option_types (for prompting and help)
    # are the same type of object being managed here.., options options options
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_option_type_option_types)
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      option_type = find_option_type_by_name_or_id(args[0])
      exit 1 if option_type.nil?

      #params = options[:options] || {}
      params = Morpheus::Cli::OptionTypes.no_prompt(update_option_type_option_types, options[:options], @api_client, options[:params])
      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end
      if params.key?('required')
        params['required'] = ['on','true'].include?(params['required'].to_s)
      end
      option_type_payload = params
      payload = {optionType: option_type_payload}
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.update(option_type['id'], payload)
        return
      end
      json_response = @option_types_interface.update(option_type['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Updated Option Type #{option_type_payload['name']}"
      #list([])
      get([option_type['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
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
      if options[:dry_run]
        print_dry_run @option_types_interface.dry.destroy(option_type['id'])
        return
      end
      json_response = @option_types_interface.destroy(option_type['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

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

  # Prompts user for exposed ports array
  # returns array of port objects
  def prompt_exposed_ports(options={}, api_client=nil, api_params={})
    #puts "Configure ports:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))

    ports = []
    port_index = 0
    has_another_port = options[:options] && options[:options]["exposedPort#{port_index}"]
    add_another_port = has_another_port || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add an exposed port?"))
    while add_another_port do
      field_context = "exposedPort#{port_index}"

      port = {}
      #port['name'] ||= "Port #{port_index}"
      port_label = port_index == 0 ? "Port" : "Port [#{port_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{port_label} Name", 'required' => false, 'description' => 'Choose a name for this port.', 'defaultValue' => port['name']}], options[:options])
      port['name'] = v_prompt[field_context]['name']

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'port', 'type' => 'number', 'fieldLabel' => "#{port_label} Number", 'required' => true, 'description' => 'A port number. eg. 8001', 'defaultValue' => (port['port'] ? port['port'].to_i : nil)}], options[:options])
      port['port'] = v_prompt[field_context]['port']

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'loadBalanceProtocol', 'type' => 'select', 'fieldLabel' => "#{port_label} LB", 'selectOptions' => load_balance_protocols, 'required' => false, 'skipSingleOption' => true, 'description' => 'Choose a load balance protocol.', 'defaultValue' => port['loadBalanceProtocol']}], options[:options])
      port['loadBalanceProtocol'] = v_prompt[field_context]['loadBalanceProtocol']

      ports << port
      port_index += 1
      has_another_port = options[:options] && options[:options]["exposedPort#{port_index}"]
      add_another_port = has_another_port || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another exposed port?"))

    end


    return ports
  end

  def find_option_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_option_type_by_id(val)
    else
      return find_option_type_by_name(val)
    end
  end

  def find_option_type_by_id(id)
    begin
      json_response = @option_types_interface.get(id.to_i)
      return json_response['optionType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Option Type not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_option_type_by_name(name)
    json_results = @option_types_interface.list({name: name.to_s})
    if json_results['optionTypes'].empty?
      print_red_alert "Option Type not found by name #{name}"
      exit 1
    end
    option_type = json_results['optionTypes'][0]
    return option_type
  end

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

  # def find_option_type_list_by_name_or_id(val)
  #   if val.to_s =~ /\A\d{1,}\Z/
  #     return find_option_type_list_by_id(val)
  #   else
  #     return find_option_type_list_by_name(val)
  #   end
  # end

  # def find_option_type_list_by_id(id)
  #   begin
  #     json_response = @option_type_lists_interface.get(id.to_i)
  #     return json_response['optionTypeList']
  #   rescue RestClient::Exception => e
  #     if e.response && e.response.code == 404
  #       print_red_alert "Option List not found by id #{id}"
  #       exit 1
  #     else
  #       raise e
  #     end
  #   end
  # end

  # def find_option_type_list_by_name(name)
  #   json_results = @option_type_lists_interface.list({name: name.to_s})
  #   if json_results['optionTypeLists'].empty?
  #     print_red_alert "Option List not found by name #{name}"
  #     exit 1
  #   end
  #   option_type_list = json_results['optionTypeLists'][0]
  #   return option_type_list
  # end

  # def get_available_option_list_types
  #   [
  #     {'name' => 'Rest', 'value' => 'rest'}, 
  #     {'name' => 'Manual', 'value' => 'manual'}
  #   ]
  # end

  # def find_option_list_type(code)
  #    get_available_option_list_types.find {|it| code == it['value'] || code == it['name'] }
  # end

  # def new_option_type_list_option_types(list_type='rest')
  #   if list_type.to_s.downcase == 'rest'
  #     [
  #       {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
  #       {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
  #       #{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_option_list_types, 'defaultValue' => 'rest', 'required' => true, 'displayOrder' => 3},
  #       {'fieldName' => 'sourceUrl', 'fieldLabel' => 'Source Url', 'type' => 'text', 'required' => true, 'description' => "A REST URL can be used to fetch list data and is cached in the appliance database.", 'displayOrder' => 4},
  #       {'fieldName' => 'ignoreSSLErrors', 'fieldLabel' => 'Ignore SSL Errors', 'type' => 'checkbox', 'defaultValue' => 'off', 'displayOrder' => 5},
  #       {'fieldName' => 'sourceMethod', 'fieldLabel' => 'Source Method', 'type' => 'select', 'selectOptions' => [{'name' => 'GET', 'value' => 'GET'}, {'name' => 'POST', 'value' => 'POST'}], 'defaultValue' => 'GET', 'required' => true, 'displayOrder' => 6},
  #       {'fieldName' => 'initialDataset', 'fieldLabel' => 'Initial Dataset', 'type' => 'code-editor', 'description' => "Create an initial json dataset to be used as the collection for this option list. It should be a list containing objects with properties 'name', and 'value'. However, if there is a translation script, that will also be passed through.", 'displayOrder' => 7},
  #       {'fieldName' => 'translationScript', 'fieldLabel' => 'Translation Script', 'type' => 'code-editor', 'description' => "Create a js script to translate the result data object into an Array containing objects with properties name, and value. The input data is provided as data and the result should be put on the global variable results.", 'displayOrder' => 8},
  #     ]
  #   elsif list_type.to_s.downcase == 'manual'
  #     [
  #       {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
  #       {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
  #       #{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Rest', 'value' => 'rest'}, {'name' => 'Manual', 'value' => 'manual'}], 'defaultValue' => 'rest', 'required' => true, 'displayOrder' => 3},
  #       {'fieldName' => 'initialDataset', 'fieldLabel' => 'Dataset', 'type' => 'code-editor', 'required' => true, 'description' => "Create an initial JSON or CSV dataset to be used as the collection for this option list. It should be a list containing objects with properties 'name', and 'value'.", 'displayOrder' => 4},
  #     ]
  #   else
  #     print_red_alert "Unknown Option List type '#{list_type}'"
  #     exit 1
  #   end
  # end

  # def update_option_type_list_option_types(list_type='rest')
  #   list = new_option_type_list_option_types(list_type)
  #   list.each {|it| 
  #     it.delete('required')
  #     it.delete('defaultValue')
  #     it.delete('skipSingleOption')
  #   }
  #   list
  # end

end
