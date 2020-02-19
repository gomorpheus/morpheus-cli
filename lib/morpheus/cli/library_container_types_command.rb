require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryContainerTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-node-types'

  register_subcommands :list, :get, :add, :update, :remove

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_container_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_container_types
    @library_layouts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_layouts
    #@library_instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_instance_types
    @provision_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).provision_types
    @option_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).option_types
    #@option_type_lists_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).option_type_lists
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    layout_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--layout ID', String, "Filter by Layout") do |val|
        layout_id = val
      end
      opts.on('--technology VALUE', String, "Filter by technology") do |val|
        params['provisionType'] = val
      end
      opts.on('--category VALUE', String, "Filter by category") do |val|
        params['category'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List node types."
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
      @library_container_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_types_interface.dry.list(layout_id, params)
        return
      end
      # do it
      json_response = @library_container_types_interface.list(layout_id, params)
      # print and/or return result
      # return 0 if options[:quiet]
      if options[:json]
        puts as_json(json_response, options, "containerTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['containerTypes'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containerTypes")
        return 0
      end
      container_types = json_response['containerTypes']
      title = "Morpheus Library - Node Types"
      subtitles = []
      if layout_id
        subtitles << "Layout: #{layout_id}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if container_types.empty?
        print cyan,"No node types found.",reset,"\n"
      else
        print_container_types_table(container_types, options)
        print_results_pagination(json_response, {:label => "node type", :n_label => "node types"})
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
      opts.footer = "Display node type details." + "\n" +
                    "[name] is required. This is the name or id of a node type."
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
    layout_id = nil
    begin
      @library_container_types_interface.setopts(options)
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @library_container_types_interface.dry.get(layout_id, arg.to_i)
        else
          print_dry_run @library_container_types_interface.dry.list(layout_id, {name:arg})
        end
        return
      end
      container_type = find_container_type_by_name_or_id(layout_id, id)
      if container_type.nil?
        return 1
      end
      # skip redundant request
      #json_response = @library_container_types_interface.get(layout_id, container_type['id'])
      json_response = {'containerType' => container_type}
      #container_type = json_response['containerType']
      if options[:json]
        puts as_json(json_response, options, "containerType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containerType")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['containerType']], options)
        return 0
      end

      print_h1 "Node Type Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Short Name" => lambda {|it| it['shortName'] },
        "Version" => lambda {|it| it['containerVersion'] },
        "Technology" => lambda {|it| format_container_type_technology(it) },
        "Category" => lambda {|it| it['category'] },
        "Virtual Image" => lambda {|it| 
          it['virtualImage'] ? it['virtualImage']['name'] : ''
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
      print_description_list(description_cols, container_type)


      evars = container_type['environmentVariables']
      if evars && evars.size > 0
        print_h2 "Environment Variables"
        evar_columns = [
          {"NAME" => lambda {|it| it['name'] } },
          {"VALUE" => lambda {|it| it['defaultValue'] } },
          {"TYPE" => lambda {|it| it['valueType'].to_s.capitalize } },
          {"EXPORT" => lambda {|it| format_boolean it['export'] } },
          {"MASKED" => lambda {|it| format_boolean it['mask'] } },
        ]
        print as_pretty_table(evars, evar_columns)
      else
        # print yellow,"No environment variables found for this node type.","\n",reset
      end

      exposed_ports = container_type['containerPorts']
      if exposed_ports && exposed_ports.size > 0
        print_h2 "Exposed Ports"
        columns = [
          #{"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"PORT" => lambda {|it| it['port'] } },
          {"LB PROTOCOL" => lambda {|it| it['loadBalanceProtocol'] } },
        ]
        print as_pretty_table(exposed_ports, columns)
      else
        # print yellow,"No exposed ports found for this node type.","\n",reset
      end

      container_scripts = container_type['containerScripts'] || container_type['scripts']
      if container_scripts && container_scripts.size > 0
        print_h2 "Scripts"
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } }
        ]
        print as_pretty_table(container_scripts, columns)
      else
        # print yellow,"No scripts found for this node type.","\n",reset
      end

      container_file_templates = container_type['containerTemplates'] || container_type['templates']
      if container_file_templates && container_file_templates.size > 0
        print_h2 "File Templates"
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } }
        ]
        print as_pretty_table(container_file_templates, columns)
      else
        # print yellow,"No scripts found for this node type.","\n",reset
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
    layout = nil
    layout_id = nil
    script_ids = nil
    file_template_ids = nil
    evars = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on('--name VALUE', String, "Name for this node type") do |val|
        params['name'] = val
      end
      opts.on('--shortName VALUE', String, "Short Name") do |val|
        params['shortName'] = val
      end
      opts.on('--version VALUE', String, "Version") do |val|
        params['containerVersion'] = val
      end
      opts.on('--technology CODE', String, "Technology. This is the provision type code.") do |val|
        params['provisionTypeCode'] = val
      end
      opts.on('--scripts x,y,z', Array, "List of Script IDs") do |val|
        script_ids = val #.collect {|it| it.to_i }
      end
      opts.on('--file-templates x,y,z', Array, "List of File Template IDs") do |val|
        file_template_ids = val #.collect {|it| it.to_i }
      end
      #build_option_type_options(opts, options, add_layout_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a node type." + "\n" +
                    "[name] is required and can be passed as --name instead."
                    "Technology --technology is required. Additional options vary by type."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      params['name'] = args[0]
    end
    begin
      # construct payload
      if layout_id
        layout = find_layout_by_name_or_id(instance_type_id)
        return 1 if layout.nil?
        layout_id = layout['id']
      end
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {}
        # support the old -O OPTION switch
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # prompt for options
        prompt_params = params.merge(:no_prompt=>options[:no_prompt]) # usually of options[:options] 
        if !params['name']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], prompt_params)
          params['name'] = v_prompt['name']
        end
        if !params['shortName']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'shortName', 'type' => 'text', 'fieldLabel' => 'Short Name', 'required' => true, 'description' => 'The short name is a lowercase name with no spaces used for display in your container list.'}], prompt_params)
          params['shortName'] = v_prompt['shortName']
        end
        if !params['containerVersion']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'containerVersion', 'type' => 'text', 'fieldLabel' => 'Version', 'required' => true}], prompt_params)
          params['containerVersion'] = v_prompt['containerVersion']
        end
        
        # prompt for all the ProvisionType.customOptionTypes
        # err, these optionTypes have the fieldContext
        # so merge them at the root level of the request.

        provision_types = @provision_types_interface.list({customSupported: true})['provisionTypes']
        if provision_types.empty?
          print_red_alert "No available provision types found!"
          return 1
        end
        provision_type_options = provision_types.collect {|it| { 'name' => it['name'], 'value' => it['code']} }
        provision_type = nil
        if !params['provisionTypeCode']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionTypeCode', 'type' => 'select', 'selectOptions' => provision_type_options, 'fieldLabel' => 'Technology', 'required' => true, 'description' => 'The type of container technology.'}], prompt_params)
          params['provisionTypeCode'] = v_prompt['provisionTypeCode']
        end
        provision_type = provision_types.find {|it| it['code'] == params['provisionTypeCode'] }
        if provision_type.nil?
          print_red_alert "Provision Type not found by code '#{params['provisionTypeCode']}'!"
          return 1
        end

        # prompt custom options for the selected provision type
        provision_type_custom_option_types = provision_type['customOptionTypes']
        provision_type_v_prompt = nil
        if (!provision_type_custom_option_types || provision_type_custom_option_types.empty?)
          # print yellow,"Sorry, no options were found for provision type #{provision_type['name']}.","\n",reset
          # return 1
        else
        
          field_group_name = provision_type_custom_option_types.first['fieldGroup'] || "#{provision_type['name']} Options"
          field_group_name = "#{provision_type['name']} Options"
          # print "\n"
          puts field_group_name
          puts "==============="
          provision_type_v_prompt = Morpheus::Cli::OptionTypes.prompt(provision_type_custom_option_types,options[:options],@api_client, {provisionTypCode: params['provisionTypeCode']})
        end
        
        # payload.deep_merge!(provision_type_v_prompt)
        
        # ENVIRONMENT VARIABLES
        if evars
          params['environmentVariables'] = evars
        else
          # prompt
          # parsed_evars = parse_environment_variables
        end

        # SCRIPTS
        if script_ids
          params['scripts'] = script_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        # FILE TEMPLATES
        if file_template_ids
          params['scripts'] = file_template_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        # payload = {'containerType' => params}
        payload['containerType'] ||= {}
        payload['containerType'].deep_merge!(params)
        if provision_type_v_prompt
          payload.deep_merge!(provision_type_v_prompt)
        end

      end
      # avoid API bug in 3.6.3
      if payload['containerType']
        payload['containerType']['config'] ||= {}
      end
      @library_container_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_types_interface.dry.create(layout_id, payload)
        return
      end

      json_response = @library_container_types_interface.create(layout_id, payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      container_type = json_response['containerType']
      print_green_success "Added Node Type #{container_type['name']}"
      get([json_response['containerType']['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    layout = nil
    layout_id = nil
    script_ids = nil
    file_template_ids = nil
    evars = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--name VALUE', String, "Name for this layout") do |val|
        params['name'] = val
      end
      opts.on('--shortName VALUE', String, "Short Name") do |val|
        params['shortName'] = val
      end
      opts.on('--version VALUE', String, "Version") do |val|
        params['containerVersion'] = val
      end
      # opts.on('--technology CODE', String, "Technology") do |val|
      #   params['provisionTypeCode'] = val
      # end
      opts.on('--scripts x,y,z', Array, "List of Script IDs") do |val|
        script_ids = val #.collect {|it| it.to_i }
      end
      opts.on('--file-templates x,y,z', Array, "List of File Template IDs") do |val|
        file_template_ids = val #.collect {|it| it.to_i }
      end
      #build_option_type_options(opts, options, update_layout_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a node type."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      container_type = find_container_type_by_name_or_id(layout_id, args[0])
      if container_type.nil?
        return 1
      end
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'containerType' => passed_options}) unless passed_options.empty?
      else
        payload = {'containerType' =>  {} }
        # option_types = update_layout_option_types(instance_type)
        # params = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
        payload.deep_merge!({'containerType' => passed_options}) unless passed_options.empty?
        
        # ENVIRONMENT VARIABLES
        if evars

        else
          # prompt
        end

        # SCRIPTS
        if script_ids
          params['scripts'] = script_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        # FILE TEMPLATES
        if file_template_ids
          params['templates'] = file_template_ids.collect {|it| it.to_i }.select { |it| it != 0 }
        else
          # prompt
        end

        if params.empty? && passed_options.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        # payload = {'containerType' => params}
        payload['containerType'] ||= {}
        payload['containerType'].deep_merge!(params)

      end
      @library_container_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_types_interface.dry.update(layout_id, container_type['id'], payload)
        return
      end
      
      json_response = @library_container_types_interface.update(layout_id, container_type['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      container_type = json_response['containerType']
      print_green_success "Updated Node Type #{container_type['name']}"
      get([container_type['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    layout_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a node type."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      container_type = find_container_type_by_name_or_id(layout_id, args[0])
      if container_type.nil?
        return 1
      end

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the node type #{container_type['name']}?", options)
        exit
      end
      @library_container_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_types_interface.dry.destroy(nil, container_type['id'])
        return
      end
      json_response = @library_container_types_interface.destroy(nil, container_type['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed Node Type #{container_type['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  ## finders are in LibraryHelper

  ## these layout methods should be consolidated as well

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


end
