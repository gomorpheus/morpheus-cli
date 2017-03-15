require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Library
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :'add-version'
  alias_subcommand :details, :get
  register_subcommands({:'option-types' => :option_types_list}, :option_types_get, :option_types_add, :option_types_update, :option_types_remove)
  register_subcommands({:'option-lists' => :option_lists_list}, :option_lists_get, :option_lists_add, :option_lists_update, :option_lists_remove)

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @custom_instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).custom_instance_types
    @provision_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).provision_types
    @option_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).option_types
    @option_type_lists_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).option_type_lists
  end

  def handle(args)
    handle_subcommand(args)
  end


  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :dry_run, :json])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @custom_instance_types_interface.dry.list(params)
        return
      end

      json_response = @custom_instance_types_interface.list(params)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      instance_types = json_response['instanceTypes']
      print "\n" ,cyan, bold, "Morpheus Custom Instance Types\n","==================", reset, "\n\n"
      if instance_types.empty?
        puts yellow,"No instance types currently configured.",reset
      else
        instance_types.each do |instance_type|
          versions = instance_type['versions'].join(', ')
          print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
          instance_type['instanceTypeLayouts'].each do |layout|
            print green, "     - #{layout['name']}\n",reset
          end
        end
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      if options[:dry_run]
        if args[0] =~ /code:/
          print_dry_run @custom_instance_types_interface.dry.list({code: args[0]})
        else
          print_dry_run @custom_instance_types_interface.dry.list({name: args[0]})
        end
        return
      end
      instance_type = find_custom_instance_type_by_name_or_code(args[0])
      exit 1 if instance_type.nil?

      if options[:json]
        print JSON.pretty_generate({instanceType: instance_type}), "\n"
        return
      end

      if instance_type.nil?
        puts yellow,"No custom instance type found by name #{name}.",reset
      else
        print "\n" ,cyan, bold, "Custom Instance Type Details\n","==================", reset, "\n\n"
        versions = instance_type['versions'].join(', ')
        print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
        instance_type['instanceTypeLayouts'].each do |layout|
          print green, "     - #{layout['name']}\n",reset
        end
        print reset,"\n"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = Morpheus::Cli::OptionTypes.prompt(add_instance_type_option_types, options[:options], @api_client, options[:params])
      instance_type_keys = ['name', 'description', 'category', 'visibility', 'environmentPrefix']
      instance_type_payload = params.select {|k,v| instance_type_keys.include?(k) }
      logo_file = nil
      if params['logo']
        filename = File.expand_path(params['logo'])
        if !File.exists?(filename)
          print_red_alert "File not found: #{filename}"
          exit 1
        end
        #instance_type_payload['logo'] = File.new(filename, 'rb')
        logo_file = File.new(filename, 'rb')
      end
      if params['hasAutoScale'] == 'on'
        instance_type_payload['hasAutoScale'] = true
      end
      if params['hasDeployment'] == 'on'
        instance_type_payload['hasDeployment'] = true
      end
      payload = {instanceType: instance_type_payload}
      if options[:dry_run]
        print_dry_run @custom_instance_types_interface.dry.create(payload)
        if logo_file
          print_dry_run @custom_instance_types_interface.dry.update_logo(":id", logo_file)
        end
        return
      end
      json_response = @custom_instance_types_interface.create(payload)

      if json_response['success']
        if logo_file
          begin
            @custom_instance_types_interface.update_logo(json_response['instanceType']['id'], logo_file)
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

      print_green_success "Added Instance Type #{instance_type_payload['name']}"
      unless options[:no_prompt]
        if ::Morpheus::Cli::OptionTypes::confirm("Add first version?", options)
          puts "\n"
          add_version(["code:#{json_response['code']}"])
        end
      end

      #list([])

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_type = find_custom_instance_type_by_name_or_code(args[0])
      exit 1 if instance_type.nil?
      # option_types = update_instance_type_option_types(instance_type)
      # params = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
      params = options[:options] || {}
      instance_type_keys = ['name', 'description', 'category', 'visibility', 'environmentPrefix']
      instance_type_payload = params.select {|k,v| instance_type_keys.include?(k) }
      logo_file = nil
      if params['logo']
        filename = File.expand_path(params['logo'])
        if !File.exists?(filename)
          print_red_alert "File not found: #{filename}"
          exit 1
        end
        #instance_type_payload['logo'] = File.new(filename, 'rb')
        logo_file = File.new(filename, 'rb')
      end
      if params['hasAutoScale'] == 'on'
        instance_type_payload['hasAutoScale'] = true
      elsif params['hasAutoScale'] == 'off'
        instance_type_payload['hasAutoScale'] = false
      end
      if params['hasDeployment'] == 'on'
        instance_type_payload['hasDeployment'] = true
      elsif params['hasDeployment'] == 'off'
        instance_type_payload['hasDeployment'] = false
      end
      if instance_type_payload.empty? && logo_file.nil?
        puts optparse
        option_lines = update_instance_type_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end
      if instance_type_payload.empty?
        # just updating logo (separate request)
        instance_type_payload['name'] = instance_type['name']
      end
      payload = {instanceType: instance_type_payload}
      if options[:dry_run]
        print_dry_run @custom_instance_types_interface.dry.update(instance_type['id'], payload)
        if logo_file
          print_dry_run @custom_instance_types_interface.dry.update_logo(":id", logo_file)
        end
        return
      end
      json_response = @custom_instance_types_interface.update(instance_type['id'], payload)

      if json_response['success']
        if logo_file
          begin
            @custom_instance_types_interface.update_logo(json_response['instanceType']['id'], logo_file)
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

      print_green_success "Updated Instance Type #{instance_type_payload['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      instance_type = find_custom_instance_type_by_name_or_code(args[0])
      exit 1 if instance_type.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the instance type #{instance_type['name']}?", options)
        exit
      end
      if options[:dry_run]
        print_dry_run @custom_instance_types_interface.dry.destroy(instance_type['id'])
        return
      end
      json_response = @custom_instance_types_interface.destroy(instance_type['id'])

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

  def add_version(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_type = find_custom_instance_type_by_name_or_code(args[0])
      exit 1 if instance_type.nil?

      #params = Morpheus::Cli::OptionTypes.prompt(add_version_option_types, options[:options], @api_client, options[:params])
      provision_types = @provision_types_interface.get({customSupported: true})['provisionTypes']
      if provision_types.empty?
        print_red_alert "No available provision types found!"
        exit 1
      end
      provision_type_options = provision_types.collect {|it| { 'name' => it['name'], 'value' => it['code']} }
      payload = {'containerType' => {}, 'instanceTypeLayout' => {}, 'instanceType' => {}}

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'instanceTypeLayout', 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'A name for this layout.'}], options[:options])
      payload['instanceTypeLayout']['name'] = v_prompt['instanceTypeLayout']['name']

      # shortName is only available for the first new version
      if !instance_type['versions'] || instance_type['versions'].size == 0
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'containerType', 'fieldName' => 'shortName', 'type' => 'text', 'fieldLabel' => 'Short Name', 'required' => true, 'description' => 'The short name is a lowercase name with no spaces used for display in your container list.'}], options[:options])
        payload['containerType']['shortName'] = v_prompt['containerType']['shortName']
      end

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'containerType', 'fieldName' => 'provisionTypeCode', 'type' => 'select', 'selectOptions' => provision_type_options, 'fieldLabel' => 'Technology', 'required' => true, 'description' => 'The type of container technology.'}], options[:options])
      payload['containerType']['provisionTypeCode'] = v_prompt['containerType']['provisionTypeCode']
      provision_type = provision_types.find {|it| it['code'] == payload['containerType']['provisionTypeCode'] }

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'instanceTypeLayout', 'fieldName' => 'instanceVersion', 'type' => 'text', 'fieldLabel' => 'Version', 'required' => true, 'description' => 'A Version Number eg. 0.0.1'}], options[:options])
      payload['instanceTypeLayout']['instanceVersion'] = v_prompt['instanceTypeLayout']['instanceVersion']

      custom_option_types = provision_type['customOptionTypes']

      if (!custom_option_types || custom_option_types.empty?)
        puts yellow,"Sorry, no options were found for #{provision_type['name']}.",reset
        exit 1
      end
      # prompt custom options for the selected provision type
      field_group_name = custom_option_types.first['fieldGroup'] || "#{provision_type['name']} Options"
      puts field_group_name
      puts "==============="
      v_prompt = Morpheus::Cli::OptionTypes.prompt(custom_option_types,options[:options],@api_client, {provisionTypCode: payload['provisionTypeCode']})

      if v_prompt['containerType']
        payload['containerType'].merge!(v_prompt['containerType'])
      end
      if v_prompt['containerType.config']
        payload['containerType']['config'] = v_prompt['containerType.config']
      end
      if v_prompt['instanceTypeLayout']
        payload['instanceTypeLayout'].merge!(v_prompt['instanceTypeLayout'])
      end
      # instanceType.backupType, which is not even persisted on the server?
      if v_prompt['instanceType']
        payload['instanceType'].merge!(v_prompt['instanceType'])
      end

      # puts "PAYLOAD:"
      # puts JSON.pretty_generate(payload)
      # puts "\nexiting early"
      # exit 0

      payload['exposedPorts'] = prompt_exposed_ports(options, @api_client)

      request_payload = payload
      json_response = @custom_instance_types_interface.create_version(instance_type['id'], request_payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Added Instance Type Version #{instance_type['name']} - #{payload['instanceTypeLayout']['instanceVersion']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  #### Option Type actions

  def option_types_list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :dry_run, :json])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

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
      print "\n" ,cyan, bold, "Morpheus Option Types\n","==================", reset, "\n\n"
      if option_types.empty?
        puts yellow,"No option types currently configured.",reset
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

  def option_types_get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @option_types_interface.dry.get(args[0].to_i)
        else
          print_dry_run @option_types_interface.dry.list({name: args[0]})
        end
        return
      end
      option_type = find_option_type_by_name_or_id(args[0])
      exit 1 if option_type.nil?

      if options[:json]
        print JSON.pretty_generate({optionType: option_type}), "\n"
        return
      end

      print "\n" ,cyan, bold, "Option Type Details\n","==================", reset, "\n\n"
      print cyan
      puts "ID: #{option_type['id']}"
      puts "Name: #{option_type['name']}"
      puts "Description: #{option_type['description']}"
      puts "Field Name: #{option_type['fieldName']}"
      puts "Type: #{option_type['type'].to_s.capitalize}"
      puts "Label: #{option_type['fieldLabel']}"
      puts "Placeholder: #{option_type['placeHolder']}"
      puts "Default Value: #{option_type['defaultValue']}"
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def option_types_add(args)
    # JD: this is annoying because our option_types (for prompting and help)
    # are the same type of object being managed here.., options options options
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[options]")
      build_option_type_options(opts, options, new_option_type_option_types)
      build_common_options(opts, options, [:options, :json, :dry_run])
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
      print_green_success "Added Option Type #{option_type_payload['name']}"
      #option_types_list([])
      option_types_get([option_type['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def option_types_update(args)
    # JD: this is annoying because our option_types (for prompting and help)
    # are the same type of object being managed here.., options options options
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_option_type_option_types)
      build_common_options(opts, options, [:options, :json, :dry_run])
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
      #option_types_list([])
      option_types_get([option_type['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def option_types_remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
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

  #### Option Type List actions

  def option_lists_list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :dry_run, :json])
      opts.footer = "This outputs a list of custom Option List records."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

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
      print "\n" ,cyan, bold, "Morpheus Option Lists\n","==================", reset, "\n\n"
      if option_type_lists.empty?
        puts yellow,"No option lists currently configured.",reset
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
        print cyan
        tp rows, [
          :id,
          :name,
          :description,
          :type,
          :size
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

  def option_lists_get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
      opts.footer = "This outputs details about a particular Option List."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
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

      print "\n" ,cyan, bold, "Option List Details\n","==================", reset, "\n\n"
      print cyan
      puts "ID: #{option_type_list['id']}"
      puts "Name: #{option_type_list['name']}"
      puts "Description: #{option_type_list['description']}"
      puts "Type: #{option_type_list['type'].to_s.capitalize}"
      if option_type_list['type'] == 'manual'
        print cyan,"Initial Dataset:","\n",reset,bright_black,"#{option_type_list['initialDataset']}","\n",reset
        print cyan
      else      
        puts "Source URL: #{option_type_list['sourceUrl']}"
        puts "Ignore SSL Errors: #{option_type_list['ignoreSSLErrors'] ? 'yes' : 'no'}"
        puts "Source Method: #{option_type_list['sourceMethod'].to_s.upcase}"
        print cyan,"Initial Dataset:","\n",reset,bright_black,"#{option_type_list['initialDataset']}","\n",reset
        print cyan
        print cyan,"Translation Script:","\n",reset,bright_black,"#{option_type_list['translationScript']}","\n",reset
        print cyan
      end
      # print "\n" ,cyan, bold, "List Items\n","==================", reset, "\n\n"
      print cyan,bold,"List Items: ",reset,"\n"
      if option_type_list['listItems']
        # puts "\tNAME\tVALUE"
        # option_type_list['listItems'].each do |list_item|
        #   puts "\t#{list_item['name']}\t#{list_item['value']}"
        # end
        print cyan
        print "\n"
        tp option_type_list['listItems'], ['name', 'value']
      else
        puts "No data"
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def option_lists_add(args)
    # JD: this is annoying because our option_types (for prompting and help)
    # are the same type of object being managed here.., options options options
    options = {}
    my_option_types = nil
    list_type = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[type] [options]")
      opts.on( '-t', '--type TYPE', "Option List Type. (rest, manual)" ) do |val|
        list_type = val
        # options[:options] ||= {}
        # options[:options]['type'] = val
      end
      build_option_type_options(opts, options, new_option_type_list_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    
    if !list_type
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_option_list_types, 'defaultValue' => 'rest', 'required' => true}], options[:options], @api_client, {})
      list_type = v_prompt['type']
    end

    connect(options)
    begin
      params = Morpheus::Cli::OptionTypes.prompt(new_option_type_list_option_types(list_type), options[:options], @api_client, options[:params])
      if params.key?('required')
        params['required'] = ['on','true'].include?(params['required'].to_s)
      end
      params['type'] = list_type
      list_payload = params
      payload = {'optionTypeList' => list_payload}
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.create(payload)
        return
      end
      json_response = @option_type_lists_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Option List #{list_payload['name']}"
      #option_lists_list([])
      option_type_list = json_response['optionTypeList']
      if option_type_list
        option_lists_get([option_type_list['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def option_lists_update(args)
    # JD: this is annoying because our option_types (for prompting and help)
    # are the same type of object being managed here.., options options options
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_option_type_list_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      option_type_list = find_option_type_list_by_name_or_id(args[0])
      exit 1 if option_type_list.nil?

      list_type = option_type_list['type']
      prompt_options = update_option_type_list_option_types(list_type)
      #params = options[:options] || {}
      params = Morpheus::Cli::OptionTypes.no_prompt(prompt_options, options[:options], @api_client, options[:params])
      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end
      if params.key?('required')
        params['required'] = ['on','true'].include?(params['required'].to_s)
      end
      list_payload = params
      payload = {optionTypeList: list_payload}
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
      #option_lists_list([])
      option_lists_get([option_type_list['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def option_lists_remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
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
      #option_lists_list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_custom_instance_type_by_code(code)
    instance_type_results = @custom_instance_types_interface.list({code: code})
    if instance_type_results['instanceTypes'].empty?
      print_red_alert "Custom Instance Type not found by code #{code}"
      return nil
    end
    return instance_type_results['instanceTypes'][0]
  end

  def find_custom_instance_type_by_name(name)
    instance_type_results = @custom_instance_types_interface.list({name: name})
    instance_types = instance_type_results['instanceTypes']
    if instance_types.empty?
      print_red_alert "Custom Instance Type not found by name #{name}"
      return nil
    elsif instance_types.size > 1
      print_red_alert "Found #{instance_types.size} instance types by name #{name}"
      print red, "\n"
      instance_types.each do |instance_type|
        print "= #{instance_type['name']} (#{instance_type['code']})\n"
      end
      print "\n", "Find by code:<code> instead"
      print reset,"\n"
      return nil
    else
      return instance_types[0]
    end
  end

  def find_custom_instance_type_by_name_or_code(val)
    if val =~ /code:/
      find_custom_instance_type_by_code(val.sub('code:', ''))
    else
      find_custom_instance_type_by_name(val)
    end
  end

  def instance_type_categories
    [
      {'name' => 'Web', 'value' => 'web'},
      {'name' => 'SQL', 'value' => 'sql'},
      {'name' => 'NoSQL', 'value' => 'nosql'},
      {'name' => 'Apps', 'value' => 'apps'},
      {'name' => 'Network', 'value' => 'network'},
      {'name' => 'Messaging', 'value' => 'messaging'},
      {'name' => 'Cache', 'value' => 'cache'},
      {'name' => 'OS', 'value' => 'os'},
      {'name' => 'Cloud', 'value' => 'cloud'},
      {'name' => 'Utility', 'value' => 'utility'}
    ]
  end

  def add_instance_type_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
      {'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'select', 'selectOptions' => instance_type_categories, 'required' => true, 'displayOrder' => 3},
      {'fieldName' => 'logo', 'fieldLabel' => 'Icon File', 'type' => 'text', 'displayOrder' => 4},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'displayOrder' => 5},
      {'fieldName' => 'environmentPrefix', 'fieldLabel' => 'Environment Prefix', 'type' => 'text', 'displayOrder' => 6, 'description' => 'Used for exportable environment variables when tying instance types together in app contexts. If not specified a name will be generated.'},
      {'fieldName' => 'hasAutoScale', 'fieldLabel' => 'Enable Scaling (Horizontal)', 'type' => 'checkbox', 'displayOrder' => 7},
      {'fieldName' => 'hasDeployment', 'fieldLabel' => 'Supports Deployments', 'type' => 'checkbox', 'displayOrder' => 8, 'description' => 'Requires a data volume be configured on each version. Files will be copied into this location.'}
    ]
  end

  def update_instance_type_option_types(instance_type=nil)
    if instance_type
      opts = add_instance_type_option_types
      opts.find {|opt| opt['fieldName'] == 'name'}['defaultValue'] = instance_type['name']
      opts
    else
      add_instance_type_option_types
    end
  end

  def add_version_option_types
    [
      {'fieldName' => 'versionNumber', 'fieldLabel' => 'Version Number', 'type' => 'text', 'required' => true, 'displayOrder' => 1}
    ]
  end

  def update_version_option_types
    add_version_option_types
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
        {'fieldName' => 'sourceMethod', 'fieldLabel' => 'Source Method', 'type' => 'select', 'selectOptions' => [{'name' => 'GET', 'value' => 'GET'}, {'name' => 'POST', 'value' => 'POST'}], 'defaultValue' => 'GET', 'required' => true, 'displayOrder' => 6},
        {'fieldName' => 'initialDataset', 'fieldLabel' => 'Initial Dataset', 'type' => 'code-editor', 'description' => "Create an initial json dataset to be used as the collection for this option list. It should be a list containing objects with properties 'name', and 'value'. However, if there is a translation script, that will also be passed through.", 'displayOrder' => 7},
        {'fieldName' => 'translationScript', 'fieldLabel' => 'Translation Script', 'type' => 'code-editor', 'description' => "Create a js script to translate the result data object into an Array containing objects with properties name, and value. The input data is provided as data and the result should be put on the global variable results.", 'displayOrder' => 8},
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

end
