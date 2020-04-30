require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryLayoutsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  # make sure LibraryHelper is loaded after ProvisioningHelper because it overwrites some methods like find_instance_type_by_name
  # ProvisioningHelper is needed just for permissions (resourcePermissions)
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-layouts'

  register_subcommands :list, :get, :add, :update, :remove, :update_permissions

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_layouts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_layouts
    @library_instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_instance_types
    @library_container_types_interface = @api_client.library_container_types
    @spec_templates_interface = @api_client.library_spec_templates
    @spec_template_types_interface = @api_client.library_spec_template_types
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
      @library_layouts_interface.setopts(options)
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
      # opts.on( nil, '--permissions', "Display permissions" ) do
      #   options[:show_perms] = true
      # end
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
    exit_code, err = 0, nil
    instance_type_id = nil
    begin
      @library_layouts_interface.setopts(options)
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
        "Instance Type" => lambda {|it| it['instanceType']['name'] rescue '' },
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

      layout_node_types = layout['containerTypes']
      if layout_node_types && layout_node_types.size > 0
        print_h2 "Node Types"
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
        # print yellow,"No node types for this layout.","\n",reset
      end

      layout_spec_templates = layout['specTemplates']
      if layout_spec_templates && layout_spec_templates.size > 0
        print_h2 "Spec Templates"
        layout_spec_templates = layout_spec_templates.sort { |a,b| a['name'] <=> b['name'] }
        spec_template_columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"TYPE" => lambda {|it| it['type']['name'] rescue '' } }
        ]
        print as_pretty_table(layout_spec_templates, spec_template_columns)
      else
        # print yellow,"No spec templates for this layout.","\n",reset
      end


      if options[:show_perms] || (layout['permissions'] && !layout['permissions'].empty?)
        print_permissions(layout['permissions'], layout_permission_excludes)
        print reset
      else
        print reset,"\n"
      end
      return exit_code, err
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    instance_type_id = nil
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
      opts.on("--creatable [on|off]", ['on','off'], "Creatable") do |val|
        params['creatable'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--technology CODE', String, "Technology") do |val|
        params['provisionTypeCode'] = val
      end
      opts.on('--min-memory VALUE', String, "Minimum Memory (MB)") do |val|
        params['memoryRequirement'] = val
      end
      opts.on("--auto-scale [on|off]", ['on','off'], "Enable Scaling (Horizontal)") do |val|
        params['hasAutoScale'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on("--convert-to-managed [on|off]", ['on','off'], "Supports Convert To Managed") do |val|
        params['supportsConvertToManaged'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--workflow ID', String, "Workflow") do |val|
        params['taskSetId'] = val.to_i
      end
      opts.on('--option-types [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          params['optionTypes'] = []
        else
          params['optionTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--node-types [x,y,z]', Array, "List of Node Type IDs") do |list|
        if list.nil?
          params['containerTypes'] = []
        else
          params['containerTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--spec-templates [x,y,z]', Array, "List of Spec Templates to include in this layout, comma separated list of names or IDs.") do |list|
        if list.nil?
          params['specTemplates'] = []
        else
          params['specTemplates'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      add_perms_options(opts, options, layout_permission_excludes)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new layout.
[instance-type] is required and can be passed as --instance-type instead.
EOT
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      #params["name"] = args[0]
      instance_type_id = args[0]
    end
    if instance_type_id.nil?
      instance_type_id = args[0]
    end
    if !instance_type_id
      puts optparse
      return 1
    end
    connect(options)
    begin
      instance_type = find_instance_type_by_name_or_id(instance_type_id)
      exit 1 if instance_type.nil?
      instance_type_id = instance_type['id']

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
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
        if params['creatable'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'creatable', 'type' => 'checkbox', 'fieldLabel' => 'Creatable', 'defaultValue' => 'on'}], options[:options])
          params['creatable'] = ['true','on'].include?(v_prompt['creatable'].to_s) if v_prompt['creatable'] != nil
        end

        provision_types = @provision_types_interface.list({customSupported: true})['provisionTypes']
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
        if params['hasAutoScale'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'hasAutoScale', 'type' => 'checkbox', 'fieldLabel' => 'Enable Scaling (Horizontal)'}], options[:options])
          params['hasAutoScale'] = ['true','on'].include?(v_prompt['hasAutoScale'].to_s) if v_prompt['hasAutoScale'] != nil
        end
        if params['supportsConvertToManaged'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'supportsConvertToManaged', 'type' => 'checkbox', 'fieldLabel' => 'Supports Convert To Managed'}], options[:options])
          params['supportsConvertToManaged'] = ['true','on'].include?(v_prompt['supportsConvertToManaged'].to_s) if v_prompt['supportsConvertToManaged'] != nil
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
        prompt_results = prompt_for_option_types(params, options, @api_client)
        if prompt_results[:success]
          params['optionTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1
        end

        # NODE TYPES
        prompt_results = prompt_for_container_types(params, options, @api_client)
        if prompt_results[:success]
          params['containerTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1
        end

        # SPEC TEMPLATES
        prompt_results = prompt_for_spec_templates(params, options, @api_client)
        if prompt_results[:success]
          params['specTemplates'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1
        end
        

        payload = {'instanceTypeLayout' => params}
        
        # Resource Permissions (Groups only for layouts)
        perms = prompt_permissions(options.merge({}), layout_permission_excludes)
        perms_payload = {}
        perms_payload['resourcePermissions'] = perms['resourcePermissions'] if !perms['resourcePermissions'].nil?
        #perms_payload['tenantPermissions'] = perms['tenantPermissions'] if !perms['tenantPermissions'].nil?

        payload['instanceTypeLayout']['permissions'] = perms_payload
        payload['instanceTypeLayout']['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

      end
      @library_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.create(instance_type_id, payload)
        return
      end

      json_response = @library_layouts_interface.create(instance_type_id, payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Added layout #{params['name']}"

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
    evars = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[layout] [options]")
      opts.on('--name VALUE', String, "Name for this layout") do |val|
        params['name'] = val
      end
      opts.on('--version VALUE', String, "Version") do |val|
        params['instanceVersion'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on("--creatable [on|off]", ['on','off'], "Creatable") do |val|
        params['creatable'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--technology CODE', String, "Technology") do |val|
        params['provisionTypeCode'] = val
      end
      opts.on('--min-memory VALUE', String, "Minimum Memory (MB)") do |val|
        params['memoryRequirement'] = val
      end
      opts.on("--auto-scale [on|off]", ['on','off'], "Enable Scaling (Horizontal)") do |val|
        params['hasAutoScale'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on("--convert-to-managed [on|off]", ['on','off'], "Supports Convert To Managed") do |val|
        params['supportsConvertToManaged'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--workflow ID', String, "Workflow") do |val|
        params['taskSetId'] = val.to_i
      end
      opts.on('--option-types [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          params['optionTypes'] = []
        else
          params['optionTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--node-types [x,y,z]', Array, "List of Node Type IDs") do |list|
        if list.nil?
          params['containerTypes'] = []
        else
          params['containerTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--spec-templates [x,y,z]', Array, "List of Spec Templates to include in this layout, comma separated list of names or IDs.") do |list|
        if list.nil?
          params['specTemplates'] = []
        else
          params['specTemplates'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      add_perms_options(opts, options, layout_permission_excludes)
      build_standard_update_options(opts, options)
            opts.footer = <<-EOT
Update a layout.
[layout] is required. This is the name or id of a layout.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    exit_code, err = 0, nil
    
      layout = find_layout_by_name_or_id(nil, args[0])
      exit 1 if layout.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # ENVIRONMENT VARIABLES
        if evars

        else
          # prompt
        end

        # OPTION TYPES
        if params['optionTypes']
          prompt_results = prompt_for_option_types(params, options, @api_client)
          if prompt_results[:success]
            params['optionTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1
          end
        end

        # NODE TYPES
        if params['containerTypes']
          prompt_results = prompt_for_container_types(params, options, @api_client)
          if prompt_results[:success]
            params['containerTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1
          end
        end

        # SPEC TEMPLATES
        if params['specTemplates']
          prompt_results = prompt_for_spec_templates(params, options, @api_client)
          if prompt_results[:success]
            params['specTemplates'] = prompt_results[:data] unless prompt_results[:data].nil?
          else
            return 1
          end
        end

        # perms
        if options[:groupAccessAll] != nil || options[:groupAccessList]
          perms = prompt_permissions(options.merge({no_prompt:true}), layout_permission_excludes)
          perms_payload = {}
          perms_payload['resourcePermissions'] = perms['resourcePermissions'] if !perms['resourcePermissions'].nil?
          params.deep_merge!({'permissions' => perms_payload}) if !perms_payload.empty?
        end
        
        params['visibility'] = options[:visibility] if !options[:visibility].nil?

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        payload = {'instanceTypeLayout' => params}

      end
      @library_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.update(nil, layout['id'], payload)
        return
      end
      
      json_response = @library_layouts_interface.update(nil, layout['id'], payload)
      
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Updated layout #{params['name'] || layout['name']}"
      #list([])
    return exit_code, err
  end

  def update_permissions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[layout]")
      add_perms_options(opts, options, layout_permission_excludes)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update layout permissions.
[layout] is required. This is the name or id of a layout.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    exit_code, err = 0, nil
    # if !is_master_account
    #   print_red_alert "Permissions only available for master account"
    #   return 1
    # end
    layout = find_layout_by_name_or_id(nil, args[0])
    return 1, "layout not found for #{args[0]}" if layout.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
      
      perms = prompt_permissions(options.merge({no_prompt:true}), layout_permission_excludes)
      perms_payload = {}
      perms_payload['resourcePermissions'] = perms['resourcePermissions'] if !perms['resourcePermissions'].nil?
      payload.deep_merge!({'permissions' => perms_payload}) if !perms_payload.empty?
      # resource_perms = {}
      # resource_perms['all'] = true if options[:groupAccessAll]
      # resource_perms['sites'] = options[:groupAccessList].collect {|site_id| {'id' => site_id.to_i}} if !options[:groupAccessList].nil?
      # if !resource_perms.empty? || !options[:tenants].nil?
      #   payload['permissions'] = {}
      #   payload['permissions']['resourcePermissions'] = resource_perms if !resource_perms.empty?
      #   payload['permissions']['tenantPermissions'] = {'accounts' => options[:tenants]} if !options[:tenants].nil?
      # end
      # if !options[:visibility].nil?
      #   payload['permissions'] = {}
      #   payload['permissions']['visibility'] = options[:visibility]
      # end
    end

    @library_layouts_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @library_layouts_interface.dry.update_permissions(layout['id'], payload)
      return
    end
    json_response = @library_layouts_interface.update_permissions(layout['id'], payload)
    render_response(json_response, options, 'instanceTypeLayout') do
      # note: this api does not return 400 when it fails?
      if json_response['success']
        print_green_success "Updated layout permissions"
      else
        print_rest_errors(json_response, options)
        exit_code, err = 3, (json_response['msg'] || "api did not return success:true")
      end
    end
    return exit_code, err
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
      @library_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_layouts_interface.dry.destroy(nil, layout['id'])
        return
      end
      json_response = @library_layouts_interface.destroy(nil, layout['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed layout #{layout['name']}"
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

  def layout_permission_excludes
    ['plans', 'groupDefaults', 'visibility', 'tenants']
  end
end
