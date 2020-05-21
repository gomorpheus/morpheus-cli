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
            required: option_type['required'] ? 'yes' : 'no',
            export: option_type['exportMeta'] ? 'yes' : 'no'
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
          :required,
          :export,
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
        "Export As Tag" => lambda {|it| it['exportMeta'].nil? ? '' : format_boolean(it['exportMeta']) },
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
        payload.deep_merge!({'optionType' => parse_passed_options(options)})
      else
        payload = {}
        payload.deep_merge!({'optionType' => parse_passed_options(options)})
        option_type_payload = Morpheus::Cli::OptionTypes.prompt(new_option_type_option_types, options[:options], @api_client)
        option_type_payload['required'] = ['on','true'].include?(option_type_payload['required'].to_s) if option_type_payload.key?('required')
        option_type_payload['exportMeta'] = ['on','true'].include?(option_type_payload['exportMeta'].to_s) if option_type_payload.key?('exportMeta')
        payload.deep_merge!({'optionType' => option_type_payload})
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
        payload.deep_merge!({'optionType' => parse_passed_options(options)})
      else
        payload = {}
        payload.deep_merge!({'optionType' => parse_passed_options(options)})
        option_type_payload = Morpheus::Cli::OptionTypes.no_prompt(update_option_type_option_types, options[:options], @api_client)
        option_type_payload['required'] = ['on','true'].include?(option_type_payload['required'].to_s) if option_type_payload.key?('required')
        option_type_payload['exportMeta'] = ['on','true'].include?(option_type_payload['exportMeta'].to_s) if option_type_payload.key?('exportMeta')
        payload.deep_merge!({'optionType' => option_type_payload})
        raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
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
      {'fieldName' => 'exportMeta', 'fieldLabel' => 'Export As Tag', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Export as Tag.', 'displayOrder' => 9},
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
