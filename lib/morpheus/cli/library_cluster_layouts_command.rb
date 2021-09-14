require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryClusterLayoutsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-cluster-layouts'

  register_subcommands :list, :get, :add, :update, :remove, :clone

  def initialize()
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_cluster_layouts_interface = @api_client.library_cluster_layouts
    @library_container_types_interface = @api_client.library_container_types
    @clusters_interface = @api_client.clusters
    @provision_types_interface = @api_client.provision_types
    @options_types_interface = @api_client.option_types
    @task_sets_interface = @api_client.task_sets
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--technology VALUE', String, "Filter by technology") do |val|
        params['provisionType'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List cluster layouts."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @library_cluster_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_layouts_interface.dry.list(params)
        return
      end
      # do it
      json_response = @library_cluster_layouts_interface.list(params)
      # print and/or return result
      # return 0 if options[:quiet]
      if options[:json]
        puts as_json(json_response, options, "layouts")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['layouts'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "layouts")
        return 0
      end
      layouts = json_response['layouts']
      title = "Morpheus Library - Cluster Layout"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles
      if layouts.empty?
        print cyan,"No cluster layouts found.",reset,"\n"
      else
        rows = layouts.collect do |layout|
          {
              id: layout['id'],
              name: layout['name'],
              cloud_type: layout_cloud_type(layout),
              version: layout['computeVersion'],
              description: layout['description']
          }
        end
        print as_pretty_table(rows, [:id, :name, :cloud_type, :version, :description], options)
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
      opts.banner = subcommand_usage("[layout]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display cluster layout details." + "\n" +
                    "[layout] is required. This is the name or id of a cluster layout."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    id_list.each do |id|

    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    begin
      @library_cluster_layouts_interface.setopts(options)
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @library_cluster_layouts_interface.dry.get(arg.to_i)
        else
          print_dry_run @library_container_types_interface.dry.list({name:arg})
        end
        return
      end
      layout = find_layout_by_name_or_id(id)
      if layout.nil?
        return 1
      end

      json_response = {'layout' => layout}

      if options[:json]
        puts as_json(json_response, options, "layout")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "layout")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['layout']], options)
        return 0
      end

      print_h1 "Cluster Layout Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Version" => lambda {|it| it['computeVersion']},
        # "Type" => lambda {|it| it['type'] ? it['type']['name'] : nil},
        "Creatable" => lambda {|it| format_boolean(it['creatable'])},
        "Cloud Type" => lambda {|it| layout_cloud_type(it)},
        "Cluster Type" => lambda {|it| it['groupType'] ? it['groupType']['name'] : nil},
        "Technology" => lambda {|it| it['provisionType'] ? it['provisionType']['code'] : nil},
        "Minimum Memory" => lambda {|it| printable_byte_size(it['memoryRequirement'])},
        "Workflow" => lambda {|it| it['taskSets'] && it['taskSets'].count > 0 ? it['taskSets'][0]['name'] : nil},
        "Description" => lambda {|it| it['description']},
        "Horizontal Scaling" => lambda {|it| format_boolean(it['hasAutoScale'])},
        "Install Docker" => lambda {|it| it['installContainerRuntime'].nil? ? nil : format_boolean(it['installContainerRuntime'])},
      }

      print_description_list(description_cols, layout)

      if (layout['environmentVariables'] || []).count > 0
        rows = layout['environmentVariables'].collect do |evar|
          {
              name: evar['name'],
              value: evar['defaultValue'],
              masked: format_boolean(evar['masked']),
              label: format_boolean(evar['export'])
          }
        end
        print_h2 "Environment Variables"
        puts as_pretty_table(rows, [:name, :value, :masked, :label])
      end

      if (layout['optionTypes'] || []).count > 0
        rows = layout['optionTypes'].collect do |opt|
          {
              label: opt['fieldLabel'],
              type: opt['type']
          }
        end
        print_h2 "Option Types"
        puts as_pretty_table(rows, [:label, :type])
      end

      ['master', 'worker'].each do |node_type|
        nodes = layout['computeServers'].reject {|it| it['nodeType'] != node_type}.collect do |server|
          container = server['containerType']
          {
              id: container['id'],
              name: container['name'],
              short_name: container['shortName'],
              version: container['containerVersion'],
              category: container['category'],
              count: server['nodeCount'],
              priority: server['priorityOrder']
          }
        end

        if nodes.count > 0
          print_h2 "#{node_type.capitalize} Nodes"
          puts as_pretty_table(nodes, [:id, :name, :short_name, :version, :category, :count, :priority])
        end
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('-n', '--name VALUE', String, "Name for this cluster layout") do |val|
        params['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('-v', '--version VALUE', String, "Version") do |val|
        params['computeVersion'] = val
      end
      opts.on('-c', '--creatable [on|off]', String, "Can be used to enable / disable creatable layout. Default is on") do |val|
        params['creatable'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-g', '--cluster-type CODE', String, "Cluster type. This is the cluster type code.") do |val|
        options[:clusterTypeCode] = val
      end
      opts.on('-t', '--technology CODE', String, "Technology. This is the provision type code.") do |val|
        options[:provisionTypeCode] = val
      end
      opts.on('-m', '--min-memory NUMBER', String, "Min memory. Assumes MB unless optional modifier specified, ex: 1GB") do |val|
        bytes = parse_bytes_param(val, '--min-memory', 'MB')
        params['memoryRequirement'] = bytes[:bytes]
      end
      opts.on('-w', '--workflow ID', String, "Workflow") do |val|
        options[:taskSetId] = val.to_i
      end
      opts.on('-s', '--auto-scale [on|off]', String, "Can be used to enable / disable horizontal scaling. Default is on") do |val|
        params['hasAutoScale'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--install-docker [on|off]', String, "Install Docker container runtime. Default is off.") do |val|
        params['installContainerRuntime'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--install-container-runtime [on|off]', String, "Install Docker container runtime. Default is off.") do |val|
        params['installContainerRuntime'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.add_hidden_option('--install-container-runtime')
      opts.on('--evars-json JSON', String, 'Environment variables JSON: {"name":"Foo", "value":"Bar", "masked":true, "export":true}' ) do |val|
        begin
          evars = JSON.parse(val.to_s)
          params['environmentVariables'] = evars.kind_of?(Array) ? evars : [evars]
        rescue JSON::ParserError => e
          print_red_alert "Unable to parse evars JSON"
          exit 1
        end
      end
      opts.on('-e', '--evars LIST', Array, "Environment variables list. Comma delimited list of name=value pairs") do |val|
        params['environmentVariables'] = val.collect do |nv|
          parts = nv.split('=')
          {'name' => parts[0].strip, 'value' => (parts.count > 1 ? parts[1].strip : '')}
        end
      end
      opts.on('-o', '--option-types LIST', Array, "Option types, comma separated list of option type IDs") do |val|
        options[:optionTypes] = val
      end
      opts.on('--masters LIST', Array, "List of master. Comma separated container types IDs in format id[/count/priority], ex: 100,101/3/0") do |val|
        options[:masters] = val
      end
      opts.on('--workers LIST', Array, "List of workers. Comma separated container types IDs in format id[/count/priority], ex: 100,101/3/1") do |val|
        options[:workers] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a cluster layout."
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
      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # prompt for options
        if params['name'].nil?
          params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options], @api_client,{})['name']
        end

        # version
        if params['computeVersion'].nil?
          params['computeVersion'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'computeVersion', 'type' => 'text', 'fieldLabel' => 'Version', 'required' => true}], options[:options], @api_client,{})['computeVersion']
        end

        # description
        if params['description'].nil?
          params['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false}], options[:options], @api_client,{})['description']
        end

        # creatable
        if params['creatable'].nil?
          params['creatable'] = Morpheus::Cli::OptionTypes.confirm("Creatable?", {:default => true}) == true
        end

        # cluster type
        if options[:clusterTypeCode]
          cluster_type = find_cluster_type_by_code(options[:clusterTypeCode])
          if cluster_type.nil?
            print_red_alert "Cluster type #{options[:clusterTypeCode]} not found"
            exit 1
          end
        else
          cluster_type_options = cluster_types.collect {|type| {'name' => type['name'], 'value' => type['code']}}
          cluster_type_code = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'groupType', 'type' => 'select', 'fieldLabel' => 'Cluster Type', 'required' => true, 'selectOptions' => cluster_type_options}], options[:options], @api_client,{}, nil, true)['groupType']
          cluster_type = cluster_types.find {|type| type['code'] == cluster_type_code}
        end

        params['groupType'] = {'id' => cluster_type['id']}

        # technology customSupported, createServer
        if options[:provisionTypeCode]
          provision_type = find_provision_type_by_code(options[:provisionTypeCode])
          if provision_type.nil?
            print_red_alert "Technology #{options[:provisionTypeCode]} not found"
            exit 1
          end
        else
          provision_type_options = provision_types.collect {|type| {'name' => type['name'], 'value' => type['code']}}
          provision_type_code = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionType', 'type' => 'select', 'fieldLabel' => 'Technology', 'required' => true, 'selectOptions' => provision_type_options}], options[:options], @api_client,{}, nil, true)['provisionType']
          provision_type = provision_types.find {|type| type['code'] == provision_type_code}
        end

        params['provisionType'] = {'id' => provision_type['id']}

        # min memory
        if params['memoryRequirement'].nil?
          memory = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memoryRequirement', 'type' => 'text', 'fieldLabel' => 'Minimum Memory (MB) [can use GB modifier]', 'required' => false, 'description' => 'Memory (MB)'}], options[:options], @api_client,{}, options[:no_prompt])['memoryRequirement']

          if memory
            bytes = parse_bytes_param(memory, 'minimum memory', 'MB')
            params['memoryRequirement'] = bytes[:bytes]
          end
        end

        # workflow
        if options[:taskSetId]
          task_set = @task_sets_interface.get(options[:taskSetId])['taskSet']

          if !task_set
            print_red_alert "Workflow #{options[:taskSetId]} not found"
            exit 1
          end
          params['taskSets'] = [{'id' => task_set['id']}]
        else
          task_set_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'taskSets', 'fieldLabel' => 'Workflow', 'type' => 'select', 'required' => false, 'optionSource' => 'taskSets'}], options[:options], @api_client, {})['taskSets']

          if task_set_id
            params['taskSets'] = [{'id' => task_set_id.to_i}]
          end
        end

        # auto scale
        if params['hasAutoScale'].nil?
          params['hasAutoScale'] = Morpheus::Cli::OptionTypes.confirm("Enable scaling?", {:default => false}) == true
        end

        # install docker
        if params['installContainerRuntime'].nil?
          params['installContainerRuntime'] = Morpheus::Cli::OptionTypes.confirm("Install Docker?", {:default => false}) == true
        end
        
        # evars?
        if params['environmentVariables'].nil?
          evars = []
          while Morpheus::Cli::OptionTypes.confirm("Add #{evars.empty? ? '' : 'another '}environment variable?", {:default => false}) do
            evars << prompt_evar(options)
          end
          params['environmentVariables'] = evars
        end

        # option types
        if options[:optionTypes]
          option_types = []
          options[:optionTypes].each do |option_type_id|
            if @options_types_interface.get(option_type_id.to_i).nil?
              print_red_alert "Option type #{option_type_id} not found"
              exit 1
            else
              option_types << {'id' => option_type_id.to_i}
            end
          end
        elsif !options[:no_prompt]
          avail_type_options = @options_types_interface.list({'max' => 1000})['optionTypes'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
          option_types = []
          while !avail_type_options.empty? && Morpheus::Cli::OptionTypes.confirm("Add #{option_types.empty? ? '' : 'another '}option type?", {:default => false}) do
            option_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'optionType', 'type' => 'select', 'fieldLabel' => 'Option Type', 'selectOptions' => avail_type_options, 'required' => false}],options[:options],@api_client,{}, options[:no_prompt], true)['optionType']

            if option_type_id
              option_types << {'id' => option_type_id.to_i}
              avail_type_options.reject! {|it| it['value'] == option_type_id}
            else
              break
            end
          end
        end

        params['optionTypes'] = option_types if option_types

        # nodes
        priority = 0
        ['master', 'worker'].each do |node_type|
          nodes = []
          if cluster_type["has#{node_type.capitalize}s"]
            if options["#{node_type}s".to_sym]
              options["#{node_type}s".to_sym].each do |container_type_id|
                node_count = 1
                if container_type_id.include?('/')
                  parts = container_type_id.split('/')
                  container_type_id = parts[0]
                  node_count = parts[1].to_i if parts.count > 1
                  priority = parts[2].to_i if parts.count > 2
                end

                if @library_container_types_interface.get(nil, container_type_id.to_i).nil?
                  print_red_alert "Container type #{container_type_id} not found"
                  exit 1
                else
                  nodes << {'nodeCount' => node_count, 'priorityOrder' => priority, 'containerType' => {'id' => container_type_id.to_i}}
                end
              end
            else
              avail_container_types = @library_container_types_interface.list(nil, {'technology' => provision_type['code'], 'max' => 1000})['containerTypes'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
              while !avail_container_types.empty? && Morpheus::Cli::OptionTypes.confirm("Add #{nodes.empty? ? '' : 'another '}#{node_type} node?", {:default => false}) do
                container_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "#{node_type}ContainerType", 'type' => 'select', 'fieldLabel' => "#{node_type.capitalize} Node", 'selectOptions' => avail_container_types, 'required' => true}],options[:options],@api_client,{}, options[:no_prompt], true)["#{node_type}ContainerType"]
                node_count = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "#{node_type}NodeCount", 'type' => 'number', 'fieldLabel' => "#{node_type.capitalize} Node Count", 'required' => true, 'defaultValue' => 1}], options[:options], @api_client, {}, options[:no_prompt])["#{node_type}NodeCount"]
                priority = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "#{node_type}Priority", 'type' => 'number', 'fieldLabel' => "#{node_type.capitalize} Priority", 'required' => true, 'defaultValue' => priority}], options[:options], @api_client, {}, options[:no_prompt])["#{node_type}Priority"]
                nodes << {'nodeCount' => node_count, 'priorityOrder' => priority, 'containerType' => {'id' => container_type_id.to_i}}
                avail_container_types.reject! {|it| it['value'] == container_type_id}
              end
            end
            priority += 1
          end
          params["#{node_type}s"] = nodes
        end
        payload = {'layout' => params}
      end

      @library_cluster_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_layouts_interface.dry.create(payload)
        return
      end

      json_response = @library_cluster_layouts_interface.create(payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Cluster Layout #{params['name']}"
      get([json_response['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('-n', '--name VALUE', String, "Name for this cluster layout") do |val|
        params['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('-v', '--version VALUE', String, "Version") do |val|
        params['computeVersion'] = val
      end
      opts.on('-c', '--creatable [on|off]', String, "Can be used to enable / disable creatable layout. Default is on") do |val|
        params['creatable'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-g', '--cluster-type CODE', String, "Cluster type. This is the cluster type code.") do |val|
        options[:clusterTypeCode] = val
      end
      opts.on('-t', '--technology CODE', String, "Technology. This is the provision type code.") do |val|
        options[:provisionTypeCode] = val
      end
      opts.on('-m', '--min-memory NUMBER', String, "Min memory. Assumes MB unless optional modifier specified, ex: 1GB") do |val|
        bytes = parse_bytes_param(val, '--min-memory', 'MB')
        params['memoryRequirement'] = bytes[:bytes]
      end
      opts.on('-w', '--workflow ID', String, "Workflow") do |val|
        options[:taskSetId] = val.to_i
      end
      opts.on(nil, '--clear-workflow', "Removes workflow from cluster layout") do
        params['taskSets'] = []
      end
      opts.on('-s', '--auto-scale [on|off]', String, "Can be used to enable / disable horizontal scaling. Default is on") do |val|
        params['hasAutoScale'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--install-docker [on|off]', String, "Install Docker container runtime. Default is off.") do |val|
        params['installContainerRuntime'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--install-container-runtime [on|off]', String, "Install Docker container runtime. Default is off.") do |val|
        params['installContainerRuntime'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.add_hidden_option('--install-container-runtime')
      opts.on('--evars-json JSON', String, 'Environment variables JSON: {"name":"Foo", "value":"Bar", "masked":true, "export":true}' ) do |val|
        begin
          evars = JSON.parse(val.to_s)
          params['environmentVariables'] = evars.kind_of?(Array) ? evars : [evars]
        rescue JSON::ParserError => e
          print_red_alert "Unable to parse evars JSON"
          exit 1
        end
      end
      opts.on('-e', '--evars LIST', Array, "Environment variables list. Comma delimited list of name=value pairs") do |val|
        params['environmentVariables'] = val.collect do |nv|
          parts = nv.split('=')
          {'name' => parts[0].strip, 'value' => (parts.count > 1 ? parts[1].strip : '')}
        end
      end
      opts.on(nil, '--clear-evars', "Removes all environment variables") do
        params['environmentVariables'] = []
      end
      opts.on('-o', '--opt-types LIST', Array, "Option types, comma separated list of option type IDs") do |val|
        options[:optionTypes] = val
      end
      opts.on(nil, '--clear-opt-types', "Removes all options") do
        params['optionTypes'] = []
      end
      opts.on('--masters LIST', Array, "List of master. Comma separated container types IDs in format id[/count/priority], ex: 100,101/3/0") do |val|
        options[:masters] = val
      end
      opts.on('--clear-masters', Array, "Removes all master nodes") do
        params['masters'] = []
      end
      opts.on('--workers LIST', Array, "List of workers. Comma separated container types IDs in format id[/count/priority], ex: 100,101/3/1") do |val|
        options[:workers] = val
      end
      opts.on('--clear-workers', Array, "Removes all worker nodes") do
        params['workers'] = []
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a cluster layout." + "\n" +
                    "[layout] is required. This is the name or id of a cluster layout."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    begin
      layout = find_layout_by_name_or_id(args[0])
      if layout.nil?
        return 1
      end

      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # cluster type
        cluster_type = nil
        if options[:clusterTypeCode]
          cluster_type = find_cluster_type_by_code(options[:clusterTypeCode])
          if cluster_type.nil?
            print_red_alert "Cluster type #{options[:clusterTypeCode]} not found"
            exit 1
          end
          params['groupType'] = {'id' => cluster_type['id']}
        end

        # technology customSupported, createServer
        if options[:provisionTypeCode]
          provision_type = find_provision_type_by_code(options[:provisionTypeCode])
          if provision_type.nil?
            print_red_alert "Technology #{options[:provisionTypeCode]} not found"
            exit 1
          end
          params['provisionType'] = {'id' => provision_type['id']}
        end

        # workflow
        if options[:taskSetId]
          task_set = @task_sets_interface.get(options[:taskSetId])['taskSet']

          if !task_set
            print_red_alert "Workflow #{options[:taskSetId]} not found"
            exit 1
          end
          params['taskSets'] = [{'id' => task_set['id']}]
        end

        # option types
        if options[:optionTypes]
          option_types = []
          options[:optionTypes].each do |option_type_id|
            if @options_types_interface.get(option_type_id.to_i).nil?
              print_red_alert "Option type #{option_type_id} not found"
              exit 1
            else
              option_types << {'id' => option_type_id.to_i}
            end
          end
          params['optionTypes'] = option_types if option_types
        end

        # nodes
        ['master', 'worker'].each do |node_type|
          nodes = []
          if options["#{node_type}s".to_sym]
            cluster_type ||= find_cluster_type_by_code(layout['groupType']['code'])

            if !cluster_type["has#{node_type.capitalize}s"]
              print_red_alert "#{node_type.capitalize}s not support for a #{cluster_type['name']}"
              exit 1
            else
              options["#{node_type}s".to_sym].each do |container_type_id|
                node_count = 1
                priority = nil
                if container_type_id.include?('/')
                  parts = container_type_id.split('/')
                  container_type_id = parts[0]
                  node_count = parts[1].to_i if parts.count > 1
                  priority = parts[2].to_i if parts.count > 2
                end

                if @library_container_types_interface.get(nil, container_type_id.to_i).nil?
                  print_red_alert "Container type #{container_type_id} not found"
                  exit 1
                else
                  node = {'nodeCount' => node_count, 'containerType' => {'id' => container_type_id.to_i}}
                  node['priorityOrder'] = priority if !priority.nil?
                  nodes << node
                end
              end
            end
            params["#{node_type}s"] = nodes
          end
        end

        if params.empty?
          print_green_success "Nothing to update"
          exit 1
        end
        payload = {'layout' => params}
      end

      @library_cluster_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_layouts_interface.dry.update(layout['id'], payload)
        return
      end

      json_response = @library_cluster_layouts_interface.update(layout['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Updated cluster Layout #{params['name']}"
          get([layout['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error updating cluster layout: #{json_response['msg'] || json_response['errors']}"
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def clone(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[layout]")
      opts.on('-n', '--name VALUE', String, "Name for new cluster layout. Defaults to 'Copy of...'") do |val|
        params['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('-v', '--version VALUE', String, "Version") do |val|
        params['computeVersion'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Clone a cluster layout." + "\n" +
          "[layout] is required. This is the name or id of a cluster layout being cloned."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      layout = find_layout_by_name_or_id(args[0])
      if layout.nil?
        return 1
      end

      if options[:payload]
        params = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      end

      @library_cluster_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_layouts_interface.dry.clone(layout['id'], params)
        return
      end

      json_response = @library_cluster_layouts_interface.clone(layout['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Cluster Layout #{params['name']}"
      get([json_response['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[layout]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a cluster layout." + "\n" +
                    "[layout] is required. This is the name or id of a cluster layout."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      layout = find_layout_by_name_or_id(args[0])
      if layout.nil?
        return 1
      end

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cluster layout #{layout['name']}?", options)
        exit
      end

      @library_cluster_layouts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_layouts_interface.dry.destroy(layout['id'])
        return
      end
      json_response = @library_cluster_layouts_interface.destroy(layout['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Removed Cluster Layout #{layout['name']}"
        else
          print_red_alert "Error removing cluster layout: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_layout_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_layout_by_id(val)
    else
      return find_layout_by_name(val)
    end
  end

  def find_layout_by_id(id)
    begin
      json_response = @library_cluster_layouts_interface.get(id.to_i)
      return json_response['layout']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Cluster layout not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_layout_by_name(name)
    layouts = @library_cluster_layouts_interface.list(instance_type_id, {name: name.to_s})['layouts']
    if layouts.empty?
      print_red_alert "Cluster layout not found by name #{name}"
      return nil
    elsif layouts.size > 1
      print_red_alert "#{layouts.size} cluster layouts found by name #{name}"
      print_layouts_table(layouts, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return layouts[0]
    end
  end

  def cluster_types
    @cluster_types ||= @clusters_interface.cluster_types['clusterTypes']
  end

  def find_cluster_type_by_code(code)
    cluster_types.find {|ct| ct['code'] == code}
  end

  def provision_types
    @provision_types ||= @provision_types_interface.list({customSupported: true, createServer: true})['provisionTypes']
  end

  def find_provision_type_by_code(code)
    provision_types.find {|it| it['code'] == code}
  end

  def printable_byte_size(val)
    val = val.to_i / 1024 / 1024
    label = 'MB'

    if val > 1024
      val = val / 1024
      label = 'GB'
    end
    "#{val} #{label}"
  end

  def layout_cloud_type(layout)
    layout['provisionType'] ? layout['provisionType']['name'] : (layout['groupType'] ? layout['groupType']['name'] : 'Standard')
  end

  def prompt_evar(options)
    name = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Variable Name', 'required' => true}], options[:options], @api_client,{})['name']
    value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'value', 'type' => 'text', 'fieldLabel' => 'Variable Value', 'required' => false}], options[:options], @api_client,{})['value']
    masked = Morpheus::Cli::OptionTypes.confirm("Variable Masked?", {:default => false}) == true
    export = Morpheus::Cli::OptionTypes.confirm("Variable Label?", {:default => false}) == true
    {'name' => name, 'value' => value, 'masked' => masked, 'export' => export}
  end
end
