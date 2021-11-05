require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryContainerScriptsCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'library-scripts'

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @container_scripts_interface = @api_client.library_container_scripts
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
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @container_scripts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.list(params)
        return
      end
      # do it
      json_response = @container_scripts_interface.list(params)
      # print result and return output
      if options[:json]
        puts as_json(json_response, options, "containerScripts")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['containerScripts'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containerScripts")
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
      @container_scripts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_scripts_interface.dry.get(container_script['id'])
        return
      end
      json_response = @container_scripts_interface.get(container_script['id'])
      container_script = json_response['containerScript']
      instances = json_response['instances'] || []
      servers = json_response['servers'] || []
      if options[:json]
        puts as_json(json_response, options, "containerScript")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containerScript")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response["containerScript"]], options)
        return 0
      end

      print_h1 "Container Script Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Type" => lambda {|it| format_container_script_type(it['scriptType']) },
        "Phase" => lambda {|it| format_container_script_phase(it['scriptPhase']) },
        "Run As User" => lambda {|it| it['runAsUser'] },
        "Sudo" => lambda {|it| format_boolean(it['sudoUser']) },
        "Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
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
    params = {} # {'scriptType' => 'bash', 'scriptPhase' => 'provision'}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('-t', '--type TYPE', "Script Type. i.e. bash, powershell. Default is bash.") do |val|
        params['scriptType'] = val
      end
      opts.on('--phase PHASE', String, "Script Phase. i.e. start, stop, preProvision, provision, postProvision, preDeploy, deploy, reconfigure, teardown. Default is provision.") do |val|
        params['scriptPhase'] = val
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
      opts.on("--sudo [on|off]", String, "Run with sudo") do |val|
        params['sudoUser'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--run-as-user VALUE", String, "Run as user") do |val|
        params['runAsUser'] = val
      end
      # opts.on("--run-as-password VALUE", String, "Run as password") do |val|
      #   params['runAsPassword'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
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
    connect(options)
    begin
      payload = nil
      arbitrary_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      create_payload = {}
      create_payload.deep_merge!(params)
      create_payload.deep_merge!(arbitrary_options)
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'containerScript' => create_payload}) unless create_payload.empty?
      else
        prompt_result = Morpheus::Cli::OptionTypes.prompt([
          {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
          {'fieldName' => 'scriptType', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => 'scriptTypes', 'defaultValue' => 'bash', 'required' => true},
          {'fieldName' => 'scriptPhase', 'fieldLabel' => 'Phase', 'type' => 'select', 'optionSource' => 'containerPhases', 'defaultValue' => 'provision', 'required' => true},
          {'fieldName' => 'script', 'fieldLabel' => 'Script', 'type' => 'code-editor', 'required' => true},
          {'fieldName' => 'runAsUser', 'fieldLabel' => 'Run As User', 'type' => 'text'},
          {'fieldName' => 'sudoUser', 'fieldLabel' => 'Sudo', 'type' => 'checkbox', 'defaultValue' => false},
        ], params.deep_merge(options[:options] || {}), @api_client)
        create_payload.deep_merge!(prompt_result)
        payload = {'containerScript' => create_payload}
      end
      @container_scripts_interface.setopts(options)
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
      opts.on('-t', '--type TYPE', "Script Type. i.e. bash, powershell. Default is bash.") do |val|
        params['scriptType'] = val
      end
      opts.on('--phase PHASE', String, "Script Phase. i.e. start, stop, preProvision, provision, postProvision, preDeploy, deploy, reconfigure, teardown. Default is provision.") do |val|
        params['scriptPhase'] = val
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
      opts.on("--sudo [on|off]", String, "Run with sudo") do |val|
        params['sudoUser'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--run-as-user VALUE", String, "Run as user") do |val|
        params['runAsUser'] = val
      end
      # opts.on("--run-as-password VALUE", String, "Run as password") do |val|
      #   params['runAsPassword'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a container script." + "\n" +
                    "[name] is required. This is the name or id of a container script."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
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
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload.deep_merge!({'containerScript' => params}) unless params.empty?
      else
        # update without prompting
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        script_payload = params
        if script_payload.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
        payload = {'containerScript' => script_payload}
      end
      @container_scripts_interface.setopts(options)
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
      @container_scripts_interface.setopts(options)
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
