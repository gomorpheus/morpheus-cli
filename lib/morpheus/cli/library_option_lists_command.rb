require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'
  
class Morpheus::Cli::LibraryOptionListsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-option-lists'
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :dry_run, :json, :remote])
      opts.footer = "This outputs a list of custom Option List records."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.list(params)
        return
      end

      json_response = @option_type_lists_interface.list(params)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      option_type_lists = json_response['optionTypeLists']
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Option Lists", subtitles, options
      if option_type_lists.empty?
        print cyan,"No option lists found.",reset,"\n"
      else
        rows = option_type_lists.collect do |option_type_list|
          {
            id: option_type_list['id'],
            name: option_type_list['name'],
            description: option_type_list['description'],
            type: option_type_list['type'],
            size: option_type_list['listItems'] ? option_type_list['listItems'].size : ''
          }
        end
      end
      columns = [
        :id,
        :name,
        :description,
        :type,
        :size
      ]
      print cyan
      print as_pretty_table(rows, columns, options)
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "This outputs details about a particular Option List."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @option_type_lists_interface.dry.get(args[0].to_i)
        else
          print_dry_run @option_type_lists_interface.dry.list({name: args[0]})
        end
        return
      end
      option_type_list = find_option_type_list_by_name_or_id(args[0])
      exit 1 if option_type_list.nil?

      if options[:json]
        print JSON.pretty_generate({optionTypeList: option_type_list}), "\n"
        return
      end

      print_h1 "Option List Details", options
      print cyan
      if option_type_list['type'] == 'manual'
        print_description_list({
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
        }, option_type_list)
        # print_h2 "Initial Dataset"
        # print bright_black,"#{option_type_list['initialDataset']}","\n",reset
      else
        option_list_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          "Source URL" => 'sourceUrl',
          "Real Time" => lambda {|it| format_boolean it['realTime'] },
          "Ignore SSL Errors" => lambda {|it| format_boolean it['ignoreSSLErrors'] },
          "Source Method" => lambda {|it| it['sourceMethod'].to_s.upcase }
        }
        source_headers = []
        if option_type_list['config'] && option_type_list['config']['sourceHeaders']
          source_headers = option_type_list['config']['sourceHeaders'].collect do |header|
            {name: header['name'], value: header['value'], masked: format_boolean(header['masked'])}
          end
          #option_list_columns["Source Headers"] = lambda {|it| source_headers.collect {|it| "#{it[:name]} #{it[:value]}"}.join("\n") }
        end
        print_description_list(option_list_columns, option_type_list)
        if source_headers && !source_headers.empty?
          print cyan
          print_h2 "Source Headers"
          print as_pretty_table(source_headers, [:name, :value, :masked], options)
        end
        if !option_type_list['initialDataset'].empty?
          print_h2 "Initial Dataset"
          print bright_black,"#{option_type_list['initialDataset']}","\n",reset
        end
        if !option_type_list['translationScript'].empty?
          print_h2 "Translation Script"
          print bright_black,"#{option_type_list['translationScript']}","\n",reset
        end
      end
      print_h2 "List Items"
      if option_type_list['listItems']
        print as_pretty_table(option_type_list['listItems'], ['name', 'value'], options)
      else
        puts "No data"
      end
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
    my_option_types = nil
    list_type = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type] [options]")
      opts.on( '-t', '--type TYPE', "Option List Type. (rest, manual)" ) do |val|
        list_type = val
        # options[:options] ||= {}
        # options[:options]['type'] = val
      end
      build_option_type_options(opts, options, new_option_type_list_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    
    
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['optionTypeList'] ||= {}
          payload['optionTypeList'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        if !list_type
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_option_list_types, 'defaultValue' => 'rest', 'required' => true}], options[:options], @api_client, {})
          list_type = v_prompt['type']
        end
        params = Morpheus::Cli::OptionTypes.prompt(new_option_type_list_option_types(list_type), options[:options], @api_client, options[:params])
        params['type'] = list_type
        if params['type'] == 'rest'
          # prompt for Source Headers
          source_headers = prompt_source_headers(options)
          if !source_headers.empty?
            params['config'] ||= {}
            params['config']['sourceHeaders'] = source_headers
          end
        end
        if params.key?('required')
          params['required'] = ['on','true'].include?(params['required'].to_s)
        end
        list_payload = params
        payload = {'optionTypeList' => list_payload}
      end
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.create(payload)
        return
      end
      json_response = @option_type_lists_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      option_type_list = json_response['optionTypeList']
      print_green_success "Added Option List #{option_type_list['name']}"
      get([option_type_list['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      return 0
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
      build_option_type_options(opts, options, update_option_type_list_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      option_type_list = find_option_type_list_by_name_or_id(args[0])
      exit 1 if option_type_list.nil?

      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['optionTypeList'] ||= {}
          payload['optionTypeList'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        list_type = option_type_list['type']
        prompt_options = update_option_type_list_option_types(list_type)
        #params = options[:options] || {}
        params = Morpheus::Cli::OptionTypes.no_prompt(prompt_options, options[:options], @api_client, options[:params])
        if list_type == 'rest'
          # parse Source Headers
          source_headers = prompt_source_headers(options.merge({no_prompt: true}))
          if !source_headers.empty?
            #params['config'] ||= option_type_list['config'] || {}
            params['config'] ||= {}
            params['config']['sourceHeaders'] = source_headers
          end
        end
        if params.empty?
          print_red_alert "Specify at least one option to update"
          puts optparse
          exit 1
        end
        if params.key?('required')
          params['required'] = ['on','true'].include?(params['required'].to_s)
        end
        list_payload = params
        payload = {'optionTypeList' => list_payload}
      end
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.update(option_type_list['id'], payload)
        return
      end
      json_response = @option_type_lists_interface.update(option_type_list['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Updated Option List #{list_payload['name']}"
      get([option_type_list['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
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
      option_type_list = find_option_type_list_by_name_or_id(args[0])
      exit 1 if option_type_list.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the option type #{option_type_list['name']}?", options)
        exit
      end
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.destroy(option_type_list['id'])
        return
      end
      json_response = @option_type_lists_interface.destroy(option_type_list['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed Option List #{option_type_list['name']}"
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

  def find_option_type_list_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_option_type_list_by_id(val)
    else
      return find_option_type_list_by_name(val)
    end
  end

  def find_option_type_list_by_id(id)
    begin
      json_response = @option_type_lists_interface.get(id.to_i)
      return json_response['optionTypeList']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Option List not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_option_type_list_by_name(name)
    json_results = @option_type_lists_interface.list({name: name.to_s})
    if json_results['optionTypeLists'].empty?
      print_red_alert "Option List not found by name #{name}"
      exit 1
    end
    option_type_list = json_results['optionTypeLists'][0]
    return option_type_list
  end

  def get_available_option_list_types
    [
      {'name' => 'Rest', 'value' => 'rest'}, 
      {'name' => 'Manual', 'value' => 'manual'}
    ]
  end

  def find_option_list_type(code)
     get_available_option_list_types.find {|it| code == it['value'] || code == it['name'] }
  end

  def new_option_type_list_option_types(list_type='rest')
    if list_type.to_s.downcase == 'rest'
      [
        {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
        {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
        #{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_option_list_types, 'defaultValue' => 'rest', 'required' => true, 'displayOrder' => 3},
        {'fieldName' => 'sourceUrl', 'fieldLabel' => 'Source Url', 'type' => 'text', 'required' => true, 'description' => "A REST URL can be used to fetch list data and is cached in the appliance database.", 'displayOrder' => 4},
        {'fieldName' => 'ignoreSSLErrors', 'fieldLabel' => 'Ignore SSL Errors', 'type' => 'checkbox', 'defaultValue' => 'off', 'displayOrder' => 5},
        {'fieldName' => 'realTime', 'fieldLabel' => 'Real Time', 'type' => 'checkbox', 'defaultValue' => 'off', 'displayOrder' => 6},
        {'fieldName' => 'sourceMethod', 'fieldLabel' => 'Source Method', 'type' => 'select', 'selectOptions' => [{'name' => 'GET', 'value' => 'GET'}, {'name' => 'POST', 'value' => 'POST'}], 'defaultValue' => 'GET', 'required' => true, 'displayOrder' => 7},
        {'fieldName' => 'initialDataset', 'fieldLabel' => 'Initial Dataset', 'type' => 'code-editor', 'description' => "Create an initial json dataset to be used as the collection for this option list. It should be a list containing objects with properties 'name', and 'value'. However, if there is a translation script, that will also be passed through.", 'displayOrder' => 8},
        {'fieldName' => 'translationScript', 'fieldLabel' => 'Translation Script', 'type' => 'code-editor', 'description' => "Create a js script to translate the result data object into an Array containing objects with properties name, and value. The input data is provided as data and the result should be put on the global variable results.", 'displayOrder' => 9},
      ]
    elsif list_type.to_s.downcase == 'manual'
      [
        {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
        {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
        #{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Rest', 'value' => 'rest'}, {'name' => 'Manual', 'value' => 'manual'}], 'defaultValue' => 'rest', 'required' => true, 'displayOrder' => 3},
        {'fieldName' => 'initialDataset', 'fieldLabel' => 'Dataset', 'type' => 'code-editor', 'required' => true, 'description' => "Create an initial JSON or CSV dataset to be used as the collection for this option list. It should be a list containing objects with properties 'name', and 'value'.", 'displayOrder' => 4},
      ]
    else
      print_red_alert "Unknown Option List type '#{list_type}'"
      exit 1
    end
  end

  def update_option_type_list_option_types(list_type='rest')
    list = new_option_type_list_option_types(list_type)
    list.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
      it.delete('skipSingleOption')
    }
    list
  end

  # returns array of header objects {name: "Auth", value: "somevalue", masked: false}
  def prompt_source_headers(options={})
    #puts "Source Headers:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    source_headers = []
    source_header_index = 0
    has_another_source_header = options[:options] && options[:options]["sourceHeader#{source_header_index}"]
    add_another_source_header = has_another_source_header || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add a Source Header?", {default: false}))
    while add_another_source_header do
      field_context = "sourceHeader#{source_header_index}"
      source_header = {}
      source_header['id'] = nil
      source_header_label = source_header_index == 0 ? "Header" : "Header [#{source_header_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{source_header_label} Name", 'required' => true, 'description' => 'HTTP Header Name.', 'defaultValue' => source_header['name']}], options[:options])
      source_header['name'] = v_prompt[field_context]['name']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'value', 'type' => 'text', 'fieldLabel' => "#{source_header_label} Value", 'required' => true, 'description' => 'HTTP Header Value', 'defaultValue' => source_header['value']}], options[:options])
      source_header['value'] = v_prompt[field_context]['value']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'masked', 'type' => 'checkbox', 'fieldLabel' => "#{source_header_label} Masked", 'required' => true, 'description' => 'Header value is secret and should not be displayed', 'defaultValue' => source_header['masked'] ? 'yes' : 'no'}], options[:options])
      source_header['masked'] = v_prompt[field_context]['masked'] if !v_prompt[field_context]['masked'].nil?
      source_headers << source_header
      source_header_index += 1
      has_another_source_header = options[:options] && options[:options]["sourceHeader#{source_header_index}"]
      add_another_source_header = has_another_source_header || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another Source Header?", {default: false}))
    end

    return source_headers
  end

end
