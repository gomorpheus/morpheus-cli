require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryOperatingSystemsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-operating-systems'

  register_subcommands :list, :get, :add, :update, :remove, :add_image, :remove_image

  def initialize()
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_operating_systems_interface = @api_client.library_operating_systems
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List os types."
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
      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.list_os_types(params)
        return
      end
      # do it
      json_response = @library_operating_systems_interface.list_os_types(params)
      # print and/or return result
      # return 0 if options[:quiet]
      if options[:json]
        puts as_json(json_response, options, "osTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['osTypes'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "osTypes")
        return 0
      end
      os_types = json_response['osTypes']
      title = "Morpheus Library - OS Types"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles
      if os_types.empty?
        print cyan,"No os types found.",reset,"\n"
      else
        rows = os_types.collect do |os_type|
          {
              id: os_type['id'],
              name: os_type['name'],
              code: os_type['code'],
              platform: os_type['platform'],
              vendor: os_type['vendor'],
              category: os_type['category'],
              family: os_type['osFamily'],
              owner: os_type['owner']['name'] ? os_type['owner']['name'] : 'System'
          }
        end
        print as_pretty_table(rows, [:id, :name, :code, :platform, :vendor, :category, :family, :owner], options)
        print_results_pagination(json_response, {})
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
      opts.banner = subcommand_usage("[osType]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display osType details." + "\n" +
                    "[osType] is required. This is the id of an osType."
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
      @library_operating_systems_interface.setopts(options)

      if options[:dry_run]
          print_dry_run @library_operating_systems_interface.dry.get(id)
        return
      end
      os_type = find_os_type_by_id(id)
      if os_type.nil?
        return 1
      end

      json_response = {'osType' => os_type}

      if options[:json]
        puts as_json(json_response, options, "osType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "osType")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['osType']], options)
        return 0
      end

      print_h1 "OsType Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Code" => lambda {|it| it['code']},
        "Platform" => lambda {|it| it['platform']},
        "Category" => lambda {|it|it['category']},
        "Vendor" => lambda {|it| it['vendor']},
        "Family" => lambda {|it| it['osFamily']},
        "Os Name" => lambda {|it| it['osName'] },
        "Install Agent" => lambda {|it| format_boolean(it['installAgent'])},
        "Bit Count" => lambda {|it| it['bitCount'] },
        "Owner" => lambda { |it| it['owner']}
      }

      print_description_list(description_cols, os_type)
      title = "OsType - Images"
      print_h2 title
        if os_type['images'].empty?
          print cyan,"No images found.",reset,"\n"
        else
          rows = os_type['images'].collect do |image|
            {
                id: image['id'],
                virtual_image_id: image['virtualImageId'],
                virtual_image_name: image['virtualImageName'],
                account: image['account'],
                cloud: image['zone']
            }
          end
          print as_pretty_table(rows, [:id, :virtual_image_id, :virtual_image_name, :account, :cloud], options)
        end

      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[osTypeImage]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display osTypeImage details." + "\n" +
                    "[osTypeImage] is required. This is the id of an osTypeImage."
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
      _get_image(arg, options)
    end
  end

  def _get_image(id)
    begin
      image = find_os_type_image_by_id(id)

      if image.nil?
        return 1
      end

      json_response = {'osTypeImage' => image}
    
      
      print_h1 "OsTypeImage Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "VirtualImage ID" => lambda {|it| it['virtualImageId'] },
        "VirtualImage Name" => lambda {|it| it['virtualImageName'] },
        "Account" => lambda {|it| it['account']},
        "Provision Type" => lambda {|it| it['provisionType']},
        "Cloud" => lambda {|it|it['zone']}
      }

      print_description_list(description_cols, image)

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
      opts.on('-n', '--name VALUE', String, "Name of OsType") do |val|
        params['name'] = val
      end
      opts.on('-c', '--code VALUE', String, "Code of OsType") do |val|
        params['code'] = val
      end
      opts.on('-p', '--platform VALUE', String, "Platform of OsType") do |val|
        params['platform'] = val
      end
      opts.on('-v', '--vendor VALUE', String, "Vendor of OsType") do |val|
        params['vendor'] = val
      end
      opts.on('-ca', '--category VALUE', String, "Category of OsType") do |val|
        params['category'] = val
      end
      opts.on('-o', '--osName VALUE', String, "OsName of OsType") do |val|
        params['osName'] = val
      end
      opts.on('-ov', '--osVersion VALUE', String, "OsVersion of OsType") do |val|
        params['osVersion'] = val
      end
      opts.on('-oc', '--osCodename VALUE', String, "OsCodename of OsType") do |val|
        params['osCodename'] = val
      end
      opts.on('-of', '--osFamily VALUE', String, "OsFamily of OsType") do |val|
        params['osFamily'] = val
      end
      opts.on('-b', '--bitCount VALUE', Integer, "BitCount of OsType") do |val|
        params['bitCount'] = val
      end
      opts.on('-i', '--cloudInitVersion VALUE', Integer, "CloudInitVersion of OsType") do |val|
        params['cloudInitVersion'] = val
      end
      opts.on('-d', '--description VALUE', String, "Description of OsType") do |val|
        params['description'] = val
      end
      opts.on('--install-agent [on|off]', String, "Install Agent? Pass true to install agent. Default is false.") do |val|
        params['installAgent'] = !['false','off','0'].include?(val.to_s)
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create an OsType."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    begin
      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # prompt for options
        prompt_if_nil(params, options, 'name', 'Name', true)
        prompt_if_nil(params, options, 'code', 'Code', true)
        prompt_if_nil(params, options, 'description', 'Description')
        prompt_if_nil(params, options, 'category', 'Category')

        if params['platform'].nil?
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'platform', 'fieldLabel' => 'Platform', 'type' => 'select', 'optionSource' => 'platforms', 'description' => 'Platform', 'required' => true}], options, @api_client, {})
            params['platform'] = v_prompt['platform']
        end

        prompt_if_nil(params, options, 'vendor', 'Vendor')
        prompt_if_nil(params, options, 'osName', 'OsName')
        prompt_if_nil(params, options, 'osVersion', 'OsVersion')
        prompt_if_nil(params, options, 'osCodename', 'OsCodename')
        prompt_if_nil(params, options, 'osFamily', 'OsFamily')

        if params['bitCount'].nil?
          params['bitCount'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'bitCount', 'type' => 'number', 'fieldLabel' => 'BitCount', 'required' => false, 'description' => 'BitCount.'}],options[:options],@api_client,{})['bitCount']
        end

        if params['cloudInitVersion'].nil?
          params['cloudInitVersion'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloudInitVersion', 'type' => 'number', 'fieldLabel' => 'CloudInitVersion', 'required' => false, 'description' => 'CloudInitVersion.'}],options[:options],@api_client,{})['cloudInitVersion']
        end

        if params['installAgent'].nil?
           params['installAgent'] = Morpheus::Cli::OptionTypes.confirm("Install Agent?", {:default => false})
        end

        payload = {'osType' => params}
      end

      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.create(payload)
        return
      end

      json_response = @library_operating_systems_interface.create(payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Os Type"
      _get(json_response['id'], {})
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[osType] [options]")
      opts.on('-n', '--name VALUE', String, "Name of OsType") do |val|
        params['name'] = val
      end
      opts.on('-c', '--code VALUE', String, "Code of OsType") do |val|
        params['code'] = val
      end
      opts.on('-p', '--platform VALUE', String, "Platform of OsType") do |val|
        params['platform'] = val
      end
      opts.on('-v', '--vendor VALUE', String, "Vendor of OsType") do |val|
        params['vendor'] = val
      end
      opts.on('-ca', '--category VALUE', String, "Category of OsType") do |val|
        params['category'] = val
      end
      opts.on('-o', '--osName VALUE', String, "OsName of OsType") do |val|
        params['osName'] = val
      end
      opts.on('-ov', '--osVersion VALUE', String, "OsVersion of OsType") do |val|
        params['osVersion'] = val
      end
      opts.on('-oc', '--osCodename VALUE', String, "OsCodename of OsType") do |val|
        params['osCodename'] = val
      end
      opts.on('-of', '--osFamily VALUE', String, "OsFamily of OsType") do |val|
        params['osFamily'] = val
      end
      opts.on('-b', '--bitCount VALUE', Integer, "BitCount of OsType") do |val|
        params['bitCount'] = val
      end
      opts.on('-i', '--cloudInitVersion VALUE', Integer, "CloudInitVersion of OsType") do |val|
        params['cloudInitVersion'] = val
      end
      opts.on('-d', '--description VALUE', String, "Description of OsType") do |val|
        params['description'] = val
      end
      opts.on('--install-agent [on|off]', String, "Install Agent? Pass true to install agent. Default is false.") do |val|
        options['installAgent'] = !['false','off','0'].include?(val.to_s)
      end

      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update an osType." + "\n" +
                    "[osType] is required. This is the id of an osType."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      os_type = find_os_type_by_id(args[0])
      return 1 if os_type.nil?
      
      payload = {
        'osType' => {}
      }

      # no prompting, just collect all user passed options
      params = {}
      params.deep_merge!(options.reject {|k,v| k.is_a?(Symbol) })
      params.deep_merge!(options[:options]) if options[:options]

      if params.empty?
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "Specify at least one option to update\n#{optparse}"
        return 1
      end
      payload['osType'].deep_merge!(params)


      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
          print_dry_run @library_operating_systems_interface.dry.update(os_type["id"], payload)
        return
      end

      json_response = @library_operating_systems_interface.update(os_type["id"], payload)

      if options[:json]
        puts as_json(json_response)
      else
        print_green_success "Updated osType #{os_type['id']}"
        get([os_type['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end
           


  def add_image(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('-o', '--osType VALUE', String, "Id of OsType") do |val|
        params['osType'] = val
      end
      opts.on('-v', '--virtualImage VALUE', String, "Id of Virtual Image") do |val|
        params['virtualImage'] = val
      end
      opts.on('-p', '--provisionType VALUE', String, "Provision Type") do |val|
        params['provisionType'] = val
      end
      opts.on('-z', '--zone VALUE', String, "Zone") do |val|
        params['zone'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create an OsType Image."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      params['osType'] = args[0]
    end
    begin
      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # prompt for options
        if params['osType'].nil?
            params['osType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'osType', 'type' => 'select', 'fieldLabel' => 'Os Type', 'required' => true, 'optionSource' => 'osTypes'}], options[:options], @api_client,{})['osType']
        end

        if params['provisionType'].nil?
            params['provisionType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionType', 'type' => 'select', 'fieldLabel' => 'Provision Type', 'required' => false, 'optionSource' => 'provisionTypes'}], options[:options], @api_client,{'cli' => true})['provisionType']
        end

        if params['zone'].nil?
            params['zone'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zone', 'type' => 'select', 'fieldLabel' => 'Cloud', 'required' => false, 'optionSource' => 'clouds'}], options[:options], @api_client,{'provisionTypeIds' => params['provisionType']})['zone']
        end

        if params['virtualImage'].nil?
            virtual_image = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'virtualImage', 'fieldLabel' => 'Virtual Image', 'type' => 'select', 'required' => true, 'optionSource' => 'osTypeVirtualImage'}], options[:options], @api_client, {'osTypeImage' => params})['virtualImage']
  
            params['virtualImage'] = virtual_image
        end

        payload = {'osTypeImage' => params}
      end

      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.create_image(payload)
        return
      end

      json_response = @library_operating_systems_interface.create_image(payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Os Type Image"
      _get_image(json_response['id'])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[osType]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete an Os Type." + "\n" +
                    "[osType] is required. This is the id of an osType."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      os_type = find_os_type_by_id(args[0])
      if os_type.nil?
        return 1
      end

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the OsType?", options)
        exit
      end

      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.destroy(os_type['id'])
        return
      end
      json_response = @library_operating_systems_interface.destroy(os_type['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Removed the OsType"
        else
          print_red_alert "Error removing osType: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def remove_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[osTypeImage]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete an Os Type Image." + "\n" +
                    "[osTypeImage] is required. This is the id of an osTypeImage."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      os_type_image = find_os_type_image_by_id(args[0])
      if os_type_image.nil?
        return 1
      end

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the OsTypeImage?", options)
        exit
      end

      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.destroy_image(os_type_image['id'])
        return
      end
      json_response = @library_operating_systems_interface.destroy_image(os_type_image['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Removed the OsTypeImage"
        else
          print_red_alert "Error removing osTypeImage: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private

  def find_os_type_by_id(id)
    begin
      json_response = @library_operating_systems_interface.get(id.to_i)
      return json_response['osType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "OsType not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_os_type_image_by_id(id)
    begin
      json_response = @library_operating_systems_interface.get_image(id.to_i)
      return json_response['osTypeImage']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "OsTypeImage not found by id #{id}"
      else
        raise e
      end
    end
  end

  def prompt_if_nil(params, options, param_key, label, required = false)
    params[param_key] ||= Morpheus::Cli::OptionTypes.prompt(
      [{ 'fieldName' => param_key, 'fieldLabel' => label, 'type' => 'text', 'required' => required }],
      options[:options], @api_client, {}
    )[param_key]
  end
end