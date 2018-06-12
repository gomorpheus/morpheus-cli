require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryLayoutsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-layouts'

  register_subcommands :list, :get, :add, :update, :remove

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_layouts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_layouts
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
    instance_type = nil
    instance_type_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--instance-type ID', String, "Filter by Instance Type") do |val|
        instance_type_id = val
      end
      opts.on('--category VALUE', String, "Filter by category") do |val|
        params['category'] = val
      end
      opts.on('--code VALUE', String, "Filter by code") do |val|
        params['code'] = val
      end
      opts.on('--technology VALUE', String, "Filter by technology") do |val|
        params['provisionType'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List layouts."
    end
    optparse.parse!(args)
    connect(options)
    begin
      # construct payload
      if instance_type_id
        instance_type = find_instance_type_by_name_or_id(instance_type_id)
        return 1 if instance_type.nil?
        instance_type_id = instance_type['id']
      end
      
      params.merge!(parse_list_options(options))

      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.list(instance_type_id, params)
        return
      end

      json_response = @library_layouts_interface.list(instance_type_id, params)
      if options[:json]
        puts as_json(json_response, options, "instanceTypeLayouts")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['instanceTypeLayouts'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instanceTypeLayouts")
        return 0
      end
      layouts = json_response['instanceTypeLayouts']
      title = "Morpheus Library - Layouts"
      subtitles = []
      if instance_type
        subtitles << "Instance Type: #{instance_type['name']}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if layouts.empty?
        print cyan,"No layouts found.",reset,"\n"
      else
        print_layouts_table(layouts, options)
        print_results_pagination(json_response, {:label => "layout", :n_label => "layouts"})
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
    instance_type_id = nil
    begin
      if options[:dry_run]
        if id.to_s =~ /\A\d{1,}\Z/
          print_dry_run @library_layouts_interface.dry.get(instance_type_id, id.to_i)
        else
          print_dry_run @library_layouts_interface.dry.list(instance_type_id, {name:id})
        end
        return
      end
      layout = find_layout_by_name_or_id(instance_type_id, id)
      if layout.nil?
        return 1
      end
      # skip redundant request
      #json_response = @library_layouts_interface.get(instance_type_id, layout['id'])
      json_response = {'instanceTypeLayout' => layout}
      #layout = json_response['instanceTypeLayout']
      if options[:json]
        puts as_json(json_response, options, "instanceTypeLayout")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instanceTypeLayout")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['instanceTypeLayout']], options)
        return 0
      end

      print_h1 "Layout Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        #"Code" => lambda {|it| it['code'] },
        "Version" => lambda {|it| it['instanceVersion'] },
        "Description" => lambda {|it| it['description'] },
        "Technology" => lambda {|it| format_layout_technology(it) },
        "Min Memory" => lambda {|it| 
          if it['memoryRequirement'].to_i != 0
            (it['memoryRequirement'].to_i / (1024*1024)).to_s + " MB"
          else
            ""
          end
        },
        "Workflow" => lambda {|it| 
          if it['taskSets']
            it['taskSets'][0]['name'] rescue ""
          else
            ""
          end
        },
        # "Category" => lambda {|it| it['category'].to_s.capitalize },
        # # "Logo" => lambda {|it| it['logo'].to_s },
        # "Visiblity" => lambda {|it| it['visibility'].to_s.capitalize },
        # "Environment Prefix" => lambda {|it| it['environmentPrefix'] },
        # "Enable Settings" => lambda {|it| format_boolean it['hasSettings'] },
        # "Enable Scaling" => lambda {|it| format_boolean it['hasAutoScale'] },
        # "Supports Deployments" => lambda {|it| format_boolean it['hasDeployment'] },
        # "Featured" => lambda {|it| format_boolean it['featured'] },
        # "Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        # "Active" => lambda {|it| format_boolean it['active'] },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, layout)

      

      layout_evars = layout['environmentVariables']
      if layout_evars && layout_evars.size > 0
        print_h2 "Environment Variables"
        evar_columns = [
          {"NAME" => lambda {|it| it['name'] } },
          {"VALUE" => lambda {|it| it['defaultValue'] } },
          {"TYPE" => lambda {|it| it['valueType'].to_s.capitalize } },
          {"EXPORT" => lambda {|it| format_boolean it['export'] } },
          {"MASKED" => lambda {|it| format_boolean it['mask'] } },
        ]
        print as_pretty_table(layout_evars, evar_columns)
      else
        # print yellow,"No environment variables found for this instance type.","\n",reset
      end

      layout_option_types = layout['optionTypes']
      if layout_option_types && layout_option_types.size > 0
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
        print as_pretty_table(layout_option_types, columns)
      else
        # print yellow,"No option types found for this layout.","\n",reset
      end

      print_h2 "Node Types"
      layout_node_types = layout['containerTypes']
      if layout_node_types && layout_node_types.size > 0
        # match UI sorting [version desc, name asc]
        # or use something simpler like one of these
        layout_node_types = layout_node_types.sort { |a,b| a['name'] <=> b['name'] }
        # layout_node_types = layout_node_types.sort { |a,b| a['sortOrder'] <=> b['sortOrder'] }
        node_type_columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"SHORT NAME" => lambda {|it| it['shortName'] } },
          {"VERSION" => lambda {|it| it['containerVersion'] } },
          {"TECHNOLOGY" => lambda {|it| it['provisionType'] ? it['provisionType']['name'] : '' } },
          {"CATEGORY" => lambda {|it| it['category'] } },
        ]
        print as_pretty_table(layout_node_types, node_type_columns)
      else
        print yellow,"No node types for this layout.","\n",reset
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
    instance_type_id = nil
    option_type_ids = nil
    node_type_ids = nil
    evars = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance-type]")
      opts.on('--instance-type ID', String, "Instance Type") do |val|
        instance_type_id = val
      end
      opts.on('--name VALUE', String, "Name for this layout") do |val|
        params['name'] = val
      end
      opts.on('--version VALUE', String, "Version") do |val|
        params['instanceVersion'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--technology CODE', String, "Technology") do |val|
        params['provisionTypeCode'] = val
      end
      opts.on('--min-memory VALUE', String, "Minimum Memory (MB)") do |val|
        params['memoryRequirement'] = val
      end
      opts.on('--workflow ID', String, "Workflow") do |val|
        params['taskSetId'] = val.to_i
      end
      opts.on('--option-types x,y,z', Array, "List of Option Type IDs") do |val|
        option_type_ids = val #.collect {|it| it.to_i }
      end
      opts.on('--node-types x,y,z', Array, "List of Node Type IDs") do |val|
        node_type_ids = val #.collect {|it| it.to_i }
      end
      #build_option_type_options(opts, options, add_layout_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a new layout." + "\n" +
                    "[instance-type] is required and can be passed as --instance-type instead."
    end
    optparse.parse!(args)
    connect(options)
    
    if instance_type_id.nil?
      instance_type_id = args[0]
    end

    if !instance_type_id
      puts optparse
      exit 1
    end

    begin
      instance_type = find_instance_type_by_name_or_id(instance_type_id)
      exit 1 if instance_type.nil?
      instance_type_id = instance_type['id']

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # v_prompt = Morpheus::Cli::OptionTypes.prompt(add_layout_option_types, options[:options], @api_client, options[:params])
        # params.deep_merge!(v_prompt)
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        if !params['name']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options])
          params['name'] = v_prompt['name']
        end
        if !params['instanceVersion']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceVersion', 'type' => 'text', 'fieldLabel' => 'Version', 'required' => true}], options[:options])
          params['instanceVersion'] = v_prompt['instanceVersion']
        end
        if !params['description']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false}], options[:options])
          params['description'] = v_prompt['description'] if v_prompt['description']
        end

        provision_types = @provision_types_interface.get({customSupported: true})['provisionTypes']
        if provision_types.empty?
          print_red_alert "No available provision types found!"
          exit 1
        end
        provision_type_options = provision_types.collect {|it| { 'name' => it['name'], 'value' => it['code']} }

        if !params['provisionTypeCode']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionTypeCode', 'type' => 'select', 'selectOptions' => provision_type_options, 'fieldLabel' => 'Technology', 'required' => true, 'description' => 'The type of container technology.'}], options[:options])
          params['provisionTypeCode'] = v_prompt['provisionTypeCode']
        else

        end
        provision_type = provision_types.find {|it| it['code'] == params['provisionTypeCode'] }

        if !params['memoryRequirement']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memoryRequirement', 'type' => 'text', 'fieldLabel' => 'Min Memory (MB)', 'required' => false, 'description' => 'This will override any memory requirement set on the virtual image'}], options[:options])
          params['memoryRequirement'] = v_prompt['memoryRequirement'] if v_prompt['memoryRequirement']
        end

        if !params['taskSetId']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'taskSetId', 'type' => 'text', 'fieldLabel' => 'Workflow ID', 'required' => false, 'description' => 'Worflow ID'}], options[:options])
          params['taskSetId'] = v_prompt['taskSetId'].to_i if v_prompt['taskSetId']
        end
        
        # ENVIRONMENT VARIABLES
        if evars

        else
          # prompt
        end

        # OPTION TYPES
        if option_type_ids
          params['optionTypes'] = option_type_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        # NODE TYPES
        if node_type_ids
          params['containerTypes'] = node_type_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end


        payload = {'instanceTypeLayout' => params}
        
      end

      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.create(instance_type_id, payload)
        return
      end

      json_response = @library_layouts_interface.create(instance_type_id, payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Added Layout #{params['name']}"

      #get([json_response['instanceTypeLayout']['id']])

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    instance_type_id = nil
    option_type_ids = nil
    node_type_ids = nil
    evars = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--name VALUE', String, "Name for this layout") do |val|
        params['name'] = val
      end
      opts.on('--version VALUE', String, "Version") do |val|
        params['instanceVersion'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      # opts.on('--technology CODE', String, "Technology") do |val|
      #   params['provisionTypeCode'] = val
      # end
      opts.on('--min-memory VALUE', String, "Minimum Memory (MB)") do |val|
        params['memoryRequirement'] = val
      end
      opts.on('--workflow ID', String, "Workflow") do |val|
        params['taskSetId'] = val.to_i
      end
      opts.on('--option-types x,y,z', Array, "List of Option Type IDs") do |val|
        option_type_ids = val #.collect {|it| it.to_i }
      end
      opts.on('--node-types x,y,z', Array, "List of Node Type IDs") do |val|
        node_type_ids = val #.collect {|it| it.to_i }
      end
      #build_option_type_options(opts, options, update_layout_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a layout."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      layout = find_layout_by_name_or_id(nil, args[0])
      exit 1 if layout.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # option_types = update_layout_option_types(instance_type)
        # params = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # ENVIRONMENT VARIABLES
        if evars

        else
          # prompt
        end

        # OPTION TYPES
        if option_type_ids
          params['optionTypes'] = option_type_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        # NODE TYPES
        if node_type_ids
          params['containerTypes'] = node_type_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        if params.empty?
          puts optparse
          exit 1
        end

        payload = {'instanceTypeLayout' => params}

      end

      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.update(nil, layout['id'], payload)
        return
      end
      
      json_response = @library_layouts_interface.update(nil, layout['id'], payload)
      
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Updated Layout #{params['name'] || layout['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a layout."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      layout = find_layout_by_name_or_id(nil, args[0])
      exit 1 if layout.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the instance type #{layout['name']}?", options)
        exit
      end
      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.destroy(nil, layout['id'])
        return
      end
      json_response = @library_layouts_interface.destroy(nil, layout['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed Layout #{layout['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_layout_by_name_or_id(instance_type_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_layout_by_id(instance_type_id, val)
    else
      return find_layout_by_name(instance_type_id, val)
    end
  end

  def find_layout_by_id(instance_type_id, id)
    begin
      json_response = @library_layouts_interface.get(instance_type_id, id.to_i)
      return json_response['instanceTypeLayout']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance Type not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_layout_by_name(instance_type_id, name)
    layouts = @library_layouts_interface.list(instance_type_id, {name: name.to_s})['instanceTypeLayouts']
    if layouts.empty?
      print_red_alert "Layout not found by name #{name}"
      return nil
    elsif layouts.size > 1
      print_red_alert "#{layouts.size} layouts found by name #{name}"
      print_layouts_table(layouts, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return layouts[0]
    end
  end

  def print_layouts_table(layouts, opts={})
    columns = [
      {"ID" => lambda {|layout| layout['id'] } },
      {"INSTANCE TYPE" => lambda {|layout| layout['instanceType'] ? layout['instanceType']['name'] : '' } },
      {"NAME" => lambda {|layout| layout['name'] } },
      {"VERSION" => lambda {|layout| layout['instanceVersion'] } },
      {"TECHNOLOGY" => lambda {|layout| format_layout_technology(layout) } },
      {"DESCRIPTION" => lambda {|layout| layout['description'] } },
      {"OWNER" => lambda {|layout| layout['account'] ? layout['account']['name'] : '' } }
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(layouts, columns, opts)
  end

  def format_layout_technology(layout)
    if layout
      layout['provisionType'] ? layout['provisionType']['name'] : ''
    else
      ""
    end
  end

  def format_instance_type_phase(val)
    val.to_s # .capitalize
  end

  def add_layout_option_types
    [
      # {'fieldName' => 'instanceTypeId', 'fieldLabel' => 'Instance Type ID', 'type' => 'text', 'required' => true, 'displayOrder' => 2, 'description' => 'The instance type this layout belongs to'},
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

  def update_layout_option_types(instance_type=nil)
    if instance_type
      opts = add_layout_option_types
      opts.find {|opt| opt['fieldName'] == 'name'}['defaultValue'] = instance_type['name']
      opts
    else
      add_layout_option_types
    end
  end


end
