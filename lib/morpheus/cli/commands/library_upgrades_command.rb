require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryUpgradesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-upgrades'

  register_subcommands :list, :get, :add, :update, :remove

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_container_upgrades_interface = @api_client.library_container_upgrades
    @library_layouts_interface = @api_client.library_layouts
    @library_instance_types_interface = @api_client.library_instance_types
    @provision_types_interface = @api_client.provision_types
    @option_types_interface = @api_client.option_types
    @option_type_lists_interface = @api_client.option_type_lists
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
      opts.banner = subcommand_usage("[instance-type]")
      # opts.on('--instance-type ID', String, "Filter by Instance Type") do |val|
      #   instance_type_id = val
      # end
      opts.on('--code VALUE', String, "Filter by code") do |val|
        params['code'] = val
      end
      # opts.on('--technology VALUE', String, "Filter by technology") do |val|
      #   params['provisionType'] = val
      # end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List upgrades." + "\n" +
                    "[instance-type] is required."
    end
    optparse.parse!(args)
    connect(options)
    # instance is required right now.
    instance_type_id = args[0] if !instance_type_id
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    begin
      # construct payload
      if instance_type_id
        instance_type = find_instance_type_by_name_or_id(instance_type_id)
        return 1 if instance_type.nil?
        instance_type_id = instance_type['id']
      end
      
      params.merge!(parse_list_options(options))
      @library_container_upgrades_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_upgrades_interface.dry.list(instance_type_id, params)
        return
      end

      json_response = @library_container_upgrades_interface.list(instance_type_id, params)
      if options[:json]
        puts as_json(json_response, options, "upgrades")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['upgrades'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "upgrades")
        return 0
      end
      upgrades = json_response['upgrades']
      title = "Morpheus Library - Upgrades"
      subtitles = []
      if instance_type
        subtitles << "Instance Type: #{instance_type['name']}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if upgrades.empty?
        print cyan,"No upgrades found for instance type.",reset,"\n"
      else
        print_upgrades_table(upgrades, options)
        print_results_pagination(json_response, {:label => "upgrade", :n_label => "upgrades"})
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about an upgrade." + "\n" +
                    "[instance-type] is required." + "\n" +
                    "[name] is required. This is the name or id of an upgrade."
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    instance_type_id = args[0]
    upgrade_id = args[1]
    instance_type = find_instance_type_by_name_or_id(instance_type_id)
    exit 1 if instance_type.nil?
    instance_type_id = instance_type['id']
    begin
      @library_container_upgrades_interface.setopts(options)
      if options[:dry_run]
        if id.to_s =~ /\A\d{1,}\Z/
          print_dry_run @library_container_upgrades_interface.dry.get(instance_type_id, upgrade_id.to_i)
        else
          print_dry_run @library_container_upgrades_interface.dry.list(instance_type_id, {name:upgrade_id})
        end
        return
      end
      upgrade = find_upgrade_by_name_or_id(instance_type_id, upgrade_id)
      if upgrade.nil?
        return 1
      end
      # skip redundant request
      #json_response = @library_container_upgrades_interface.get(instance_type_id, upgrade['id'])
      json_response = {'upgrade' => upgrade}
      #upgrade = json_response['upgrade']
      if options[:json]
        puts as_json(json_response, options, "upgrade")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "upgrade")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['upgrade']], options)
        return 0
      end

      print_h1 "Morpheus Upgrade Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Code" => lambda {|it| it['code'] },
        "Description" => lambda {|it| it['description'] },
        "From Version" => lambda {|it| it['srcVersion'] },
        "To Version" => lambda {|it| it['tgtVersion'] },
      }
      print_description_list(description_cols, upgrade)


      from_layout = upgrade['instanceTypeLayout']
      to_layout = upgrade['targetInstanceTypeLayout']
      layout_columns = [
          {"NAME" => lambda {|it| it['name'] } },
          {"VERSION" => lambda {|it| it['instanceVersion'] } },
        ]
      if from_layout
        print_h2 "Source Layout"
        print as_pretty_table(from_layout, layout_columns)
      end

      if to_layout
        print_h2 "Target Layout"
        print as_pretty_table(to_layout, layout_columns)
      end

      if upgrade['upgradeCommand']
        print_h2 "Upgrade Command"
        puts upgrade['upgradeCommand']
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
      opts.banner = subcommand_usage("[instance-type] [name]")
      opts.on('--instance-type ID', String, "Instance Type this upgrade belongs to") do |val|
        instance_type_id = val
      end
      opts.on('--name VALUE', String, "Name for this upgrade") do |val|
        params['name'] = val
      end
      opts.on('--code CODE', String, "Code") do |val|
        params['code'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--source-layout ID', String, "Source Layout ID to upgrade from") do |val|
        params['instanceTypeLayout'] = {'id' => val}
      end
      opts.on('--target-layout ID', String, "Target Layout ID to upgrade to") do |val|
        params['targetInstanceTypeLayout'] = {'id' => val}
      end
      opts.on('--upgradeCommand TEXT', String, "Upgrade Command") do |val|
        params['upgradeCommand'] = val
      end
      
      #build_option_type_options(opts, options, add_upgrade_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a new upgrade." + "\n" +
                    "[instance-type] is required."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      instance_type_id = args[0]
    end
    if args[1]
      params['name'] = args[1]
    end
    begin
      # find the instance type first, or just prompt for that too please.
      if !instance_type_id
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "missing required argument [instance-type]\n#{optparse}"
        return 1
      end
      instance_type = find_instance_type_by_name_or_id(instance_type_id)
      return 1 if instance_type.nil?
      instance_type_id = instance_type['id']

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {'upgrade' => {}}
        
        # support old -O options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # Name
        if params['name']
          payload['upgrade']['name'] = params['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options])
          payload['upgrade']['name'] = v_prompt['name'] if v_prompt['name']
        end

        # Source Layout
        if !params['instanceTypeLayout']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceTypeLayout', 'type' => 'text', 'fieldLabel' => 'Source Layout', 'required' => true}], options[:options])
          source_layout_id = v_prompt['instanceTypeLayout']
          params['name'] = v_prompt['instanceTypeLayout']
        end
        

        # provision_types = @provision_types_interface.list({customSupported: true})['provisionTypes']
        # if provision_types.empty?
        #   print_red_alert "No available provision types found!"
        #   exit 1
        # end
        # provision_type_options = provision_types.collect {|it| { 'name' => it['name'], 'value' => it['code']} }

        # if !params['provisionTypeCode']
        #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionTypeCode', 'type' => 'select', 'selectOptions' => provision_type_options, 'fieldLabel' => 'Technology', 'required' => true, 'description' => 'The type of container technology.'}], options[:options])
        #   params['provisionTypeCode'] = v_prompt['provisionTypeCode']
        # else

        # end
        # provision_type = provision_types.find {|it| it['code'] == params['provisionTypeCode'] }

        # get available layouts
        #available_layouts = instance_type['instanceTypeLayouts']
        available_source_layouts = @library_layout_interface.list(instance_type_id)['instanceTypeLayouts']
      
        # Source Layout
        if params['instanceTypeLayout']
          payload['upgrade']['instanceTypeLayout'] = params['instanceTypeLayout']
        else
          if available_source_layouts.empty?
            print_red_alert "No available source layouts found!"
            return 1
          end
          source_layout_dropdown_options = available_source_layouts.collect {|it| { 'name' => it['name'], 'value' => it['code']} }
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceTypeLayout', 'type' => 'select', 'selectOptions' => source_layout_dropdown_options, 'fieldLabel' => 'Source Layout', 'required' => true, 'description' => 'The source layout to upgrade from.'}], options[:options])
          payload['upgrade']['instanceTypeLayout'] = {'id' => v_prompt['instanceTypeLayout'] }
        end

        # Target Layout
        if params['targetInstanceTypeLayout']
          payload['upgrade']['targetInstanceTypeLayout'] = params['targetInstanceTypeLayout']
        else
          available_target_layouts = available_source_layouts.select {|it| it['id'] != params['instanceTypeLayout']['id'] }
          # available_target_layouts = @library_layout_interface.list(instance_type_id)['instanceTypeLayouts']
          if available_target_layouts.empty?
            print_red_alert "No available target layouts found!"
            return 1
          end
          target_layout_dropdown_options = available_target_layouts.collect {|it| { 'name' => it['name'], 'value' => it['code']} }
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetInstanceTypeLayout', 'type' => 'select', 'selectOptions' => target_layout_dropdown_options, 'fieldLabel' => 'Target Layout', 'required' => true, 'description' => 'The target layout to upgrade to.'}], options[:options])
          payload['upgrade']['targetInstanceTypeLayout'] = {'id' => v_prompt['targetInstanceTypeLayout'] }
        end

        # Upgrade Command
        if params['upgradeCommand']
          payload['upgrade']['upgradeCommand'] = params['upgradeCommand']
        else
          if ::Morpheus::Cli::OptionTypes::confirm("Enter Upgrade Command?", options.merge({default: false}))
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'code', 'fieldLabel' => 'Upgrade Command', 'required' => false}], options[:options])
            payload['upgrade']['upgradeCommand'] = v_prompt['upgradeCommand'] if v_prompt['upgradeCommand']
          end
        end

        # any other options or custom option types?

      end
      @library_container_upgrades_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_upgrades_interface.dry.create(instance_type_id, payload)
        return
      end
      # do it
      json_response = @library_container_upgrades_interface.create(instance_type_id, payload)
      # print and return result
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      upgrade = json_response['upgrade']
      print_green_success "Added upgrade #{upgrade['name']}"
      get(instance_type_id, [upgrade['id']])
      return 0
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
      opts.on('--name VALUE', String, "Name for this upgrade") do |val|
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
      #build_option_type_options(opts, options, update_upgrade_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a upgrade."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      upgrade = find_upgrade_by_name_or_id(nil, args[0])
      exit 1 if upgrade.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # option_types = update_upgrade_option_types(instance_type)
        # params = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # ENVIRONMENT VARIABLES
        if evars

        else
          # prompt
        end

        # OPTION TYPES
        if option_type_ids
          params['optionTypes'] = option_type_ids.collect {|it| it.to_i }
        else
          # prompt
        end

        # NODE TYPES
        if node_type_ids
          params['containerTypes'] = node_type_ids.collect {|it| it.to_i }
        else
          # prompt
        end

        if params.empty?
          puts optparse
          exit 1
        end

        payload = {'upgrade' => params}

      end
      @library_container_upgrades_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_upgrades_interface.dry.update(nil, upgrade['id'], payload)
        return
      end
      
      json_response = @library_container_upgrades_interface.update(nil, upgrade['id'], payload)
      
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Updated upgrade #{params['name'] || upgrade['name']}"
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
      opts.footer = "Delete a upgrade."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      upgrade = find_upgrade_by_name_or_id(nil, args[0])
      exit 1 if upgrade.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the upgrade #{upgrade['name']}?", options)
        exit
      end
      @library_container_upgrades_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_container_upgrades_interface.dry.destroy(nil, upgrade['id'])
        return
      end
      json_response = @library_container_upgrades_interface.destroy(nil, upgrade['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed upgrade #{upgrade['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_upgrade_by_name_or_id(instance_type_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_upgrade_by_id(instance_type_id, val)
    else
      return find_upgrade_by_name(instance_type_id, val)
    end
  end

  def find_upgrade_by_id(instance_type_id, id)
    begin
      json_response = @library_container_upgrades_interface.get(instance_type_id, id.to_i)
      return json_response['upgrade']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Upgrade not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_upgrade_by_name(instance_type_id, name)
    upgrades = @library_container_upgrades_interface.list(instance_type_id, {name: name.to_s})['upgrades']
    if upgrades.empty?
      print_red_alert "Upgrade not found by name #{name}"
      return nil
    elsif upgrades.size > 1
      print_red_alert "#{upgrades.size} upgrades found by name #{name}"
      print_upgrades_table(upgrades, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return upgrades[0]
    end
  end

  def print_upgrades_table(upgrades, opts={})
    columns = [
      {"ID" => lambda {|upgrade| upgrade['id'] } },
      # {"INSTANCE TYPE" => lambda {|upgrade| upgrade['instanceType'] ? upgrade['instanceType']['name'] : '' } },
      {"NAME" => lambda {|upgrade| upgrade['name'] } },
      {"FROM VERSION" => lambda {|upgrade| upgrade['srcVersion'] } },
      {"TO VERSION" => lambda {|upgrade| upgrade['tgtVersion'] } },
      # {"FROM" => lambda {|upgrade| upgrade['instanceTypeLayout'] ? ['instanceTypeLayout']['instanceVersion'] : '' } },
      # {"TO" => lambda {|upgrade| upgrade['targetInstanceTypeLayout'] ? ['targetInstanceTypeLayout']['instanceVersion'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(upgrades, columns, opts)
  end

  def add_upgrade_option_types
    [
      # {'fieldName' => 'instanceTypeId', 'fieldLabel' => 'Instance Type ID', 'type' => 'text', 'required' => true, 'displayOrder' => 2, 'description' => 'The instance type this upgrade belongs to'},
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

  def update_upgrade_option_types(instance_type=nil)
    if instance_type
      opts = add_upgrade_option_types
      opts.find {|opt| opt['fieldName'] == 'name'}['defaultValue'] = instance_type['name']
      opts
    else
      add_upgrade_option_types
    end
  end


end
