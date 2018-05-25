require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryContainerScriptsCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'library-scripts'

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @container_scripts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_container_scripts
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
      opts.footer = "List container scripts."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      # dry run?
      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.list(params)
        return
      end
      # do it
      json_response = @container_scripts_interface.list(params)
      container_scripts = json_response['containerScripts']
      if options[:include_fields]
        json_response = {"containerScripts" => filter_data(json_response["containerScripts"], options[:include_fields]) }
      end
      # print result and return output
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['containerScripts'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      end
      container_scripts = json_response['containerScripts']
      title = "Morpheus Library - Scripts"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if container_scripts.empty?
        print cyan,"No container scripts found.",reset,"\n"
      else
        print_container_scripts_table(container_scripts, options)
        print_results_pagination(json_response, {:label => "container script", :n_label => "container scripts"})
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

    begin
      container_script = find_container_script_by_name_or_id(id)
      if container_script.nil?
        return 1
      end
      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.get(container_script['id'])
        return
      end
      json_response = @container_scripts_interface.get(container_script['id'])
      container_script = json_response['containerScript']
      instances = json_response['instances'] || []
      servers = json_response['servers'] || []
      if options[:include_fields]
        json_response = {"containerScript" => filter_data(json_response["containerScript"], options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['containerScript']], options)
        return 0
      end

      print_h1 "Container Script Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Type" => lambda {|it| format_container_script_type(it['scriptType']) },
        "Phase" => lambda {|it| format_container_script_phase(it['scriptPhase']) },
        "Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        # "Enabled" => lambda {|it| format_boolean it['enabled'] },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, container_script)

      print_h2 "Script"

      puts container_script['script']

      

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {'scriptType' => 'bash', 'scriptPhase' => 'provision'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--type [bash|powershell]', String, "Script Type. Default is 'bash'") do |val|
        params['scriptType'] = val
      end
      opts.on('--phase [provision|start|stop]', String, "Script Phase. Default is 'provision'") do |val|
        params['scriptPhase'] = val
      end
      opts.on('--category VALUE', String, "Category") do |val|
        params['category'] = val
      end
      opts.on('--script TEXT', String, "Contents of the script.") do |val|
        params['script'] = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          params['script'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
        # use the filename as the name by default.
        if !params['name']
          params['name'] = File.basename(full_filename)
        end
      end
      # opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
      #   options['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new container script." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    # support [name] as first argument
    if args[0]
      params['name'] = args[0]
    end
    if !params['name']
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # todo: prompt?
        payload = {'containerScript' => params}
      end
      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.create(payload)
        return
      end
      json_response = @container_scripts_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        container_script = json_response['containerScript']
        print_green_success "Added container script #{container_script['name']}"
        _get(container_script['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      # opts.on('--code VALUE', String, "Code") do |val|
      #   params['code'] = val
      # end
      # opts.on('--description VALUE', String, "Description") do |val|
      #   params['description'] = val
      # end
      opts.on('--type [bash|powershell]', String, "Script Type") do |val|
        params['scriptType'] = val
      end
      opts.on('--phase [start|stop]', String, "Script Phase") do |val|
        params['scriptPhase'] = val
      end
      opts.on('--category VALUE', String, "Category") do |val|
        params['category'] = val
      end
      opts.on('--script TEXT', String, "Contents of the script.") do |val|
        params['script'] = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          params['script'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      # opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
      #   options['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a container script." + "\n" +
                    "[name] is required. This is the name or id of a container script."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      container_script = find_container_script_by_name_or_id(args[0])
      if container_script.nil?
        return 1
      end
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload = {'containerScript' => params}
      end
      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.update(container_script["id"], payload)
        return
      end
      json_response = @container_scripts_interface.update(container_script["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated container script #{container_script['name']}"
        _get(container_script['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :auto_confirm])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      container_script = find_container_script_by_name_or_id(args[0])
      if container_script.nil?
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete container script '#{container_script['name']}'?", options)
        return false
      end

      # payload = {
      #   'containerScript' => {id: container_script["id"]}
      # }
      # payload['containerScript'].merge!(container_script)
      payload = params

      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.destroy(container_script["id"])
        return
      end

      json_response = @container_scripts_interface.destroy(container_script["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted container script #{container_script['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def find_container_script_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_container_script_by_id(val)
    else
      return find_container_script_by_name(val)
    end
  end

  def find_container_script_by_id(id)
    begin
      json_response = @container_scripts_interface.get(id.to_i)
      return json_response['containerScript']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Container Script not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_container_script_by_name(name)
    container_scripts = @container_scripts_interface.list({name: name.to_s})['containerScripts']
    if container_scripts.empty?
      print_red_alert "Container Script not found by name #{name}"
      return nil
    elsif container_scripts.size > 1
      print_red_alert "#{container_scripts.size} container scripts found by name #{name}"
      print_container_scripts_table(container_scripts, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return container_scripts[0]
    end
  end

  def print_container_scripts_table(container_scripts, opts={})
    columns = [
      {"ID" => lambda {|container_script| container_script['id'] } },
      {"NAME" => lambda {|container_script| container_script['name'] } },
      {"TYPE" => lambda {|container_script| format_container_script_type(container_script['scriptType']) } },
      {"PHASE" => lambda {|container_script| format_container_script_phase(container_script['scriptPhase']) } },
      {"OWNER" => lambda {|container_script| container_script['account'] ? container_script['account']['name'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(container_scripts, columns, opts)
  end

  def format_container_script_type(val)
    val.to_s # .capitalize
  end

  def format_container_script_phase(val)
    val.to_s # .capitalize
  end

end
