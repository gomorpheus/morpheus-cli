require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryResourceSpecsCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'library-spec-templates'

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @resource_specs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_resource_specs
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
      opts.footer = "List resource spec templates."
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
      @resource_specs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_specs_interface.dry.list(params)
        return
      end
      # do it
      json_response = @resource_specs_interface.list(params)
      # print result and return output
      if options[:json]
        puts as_json(json_response, options, "specs")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['specTemplates'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "specs")
        return 0
      end
      resource_specs = json_response['specTemplates']
      title = "Morpheus Library - Resource Spec Templates"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if resource_specs.empty?
        print cyan,"No resource specs found.",reset,"\n"
      else
        print_resource_specs_table(resource_specs, options)
        print_results_pagination(json_response)
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
      resource_spec = find_resource_spec_by_name_or_id(id)
      if resource_spec.nil?
        return 1
      end
      @resource_specs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_specs_interface.dry.get(resource_spec['id'])
        return
      end
      json_response = @resource_specs_interface.get(resource_spec['id'])
      resource_spec = json_response['specTemplate']
      instances = json_response['instances'] || []
      servers = json_response['servers'] || []
      if options[:json]
        puts as_json(json_response, options, 'specTemplate')
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, 'specTemplate')
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['specTemplate']], options)
        return 0
      end

      print_h1 "Resource Spec Details"
      print cyan
      detemplateion_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Type" => lambda {|it| format_resource_spec_type(it['templateType']) },
        "Source" => lambda {|it| it['source'] },
        #"Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Created By" => lambda {|it| it['createdBy'] },
        "Updated By" => lambda {|it| it['updatedBy'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_detemplateion_list(detemplateion_cols, resource_spec)

      print_h2 "Content"

      puts resource_spec['content']

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {'templateType' => 'bash', 'templatePhase' => 'provision'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--type [kubernetes|helm|terraform]', String, "Spec Template Type.") do |val|
        params['templateType'] = val
      end
      # opts.on('--phase [provision|start|stop]', String, "Template Phase. Default is 'provision'") do |val|
      #   params['templatePhase'] = val
      # end
      opts.on('--category VALUE', String, "Category") do |val|
        params['category'] = val
      end
      opts.on('--template TEXT', String, "Contents of the template.") do |val|
        params['template'] = val
      end
      opts.on('--file FILE', "File containing the template. This can be used instead of --template" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          params['template'] = File.read(full_filename)
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
      opts.footer = "Create a new spec template." + "\n" +
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
        payload = {'specTemplate' => params}
      end
      @resource_specs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_specs_interface.dry.create(payload)
        return
      end
      json_response = @resource_specs_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        resource_spec = json_response['specTemplate']
        print_green_success "Added spec template #{resource_spec['name']}"
        _get(resource_spec['id'], {})
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
      # opts.on('--detemplateion VALUE', String, "Detemplateion") do |val|
      #   params['detemplateion'] = val
      # end
      opts.on('--type [bash|powershell]', String, "Template Type") do |val|
        params['templateType'] = val
      end
      opts.on('--phase [start|stop]', String, "Template Phase") do |val|
        params['templatePhase'] = val
      end
      opts.on('--category VALUE', String, "Category") do |val|
        params['category'] = val
      end
      opts.on('--template TEXT', String, "Contents of the template.") do |val|
        params['template'] = val
      end
      opts.on('--file FILE', "File containing the template. This can be used instead of --template" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          params['template'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      # opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
      #   options['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a spec template." + "\n" +
                    "[name] is required. This is the name or id of a spec template."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      resource_spec = find_resource_spec_by_name_or_id(args[0])
      if resource_spec.nil?
        return 1
      end
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload = {'specTemplate' => params}
      end
      @resource_specs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_specs_interface.dry.update(resource_spec["id"], payload)
        return
      end
      json_response = @resource_specs_interface.update(resource_spec["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated spec template #{resource_spec['name']}"
        _get(resource_spec['id'], {})
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
      resource_spec = find_resource_spec_by_name_or_id(args[0])
      if resource_spec.nil?
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete spec template '#{resource_spec['name']}'?", options)
        return false
      end

      # payload = {
      #   'specTemplate' => {id: resource_spec["id"]}
      # }
      # payload['specTemplate'].merge!(resource_spec)
      payload = params
      @resource_specs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @resource_specs_interface.dry.destroy(resource_spec["id"])
        return
      end

      json_response = @resource_specs_interface.destroy(resource_spec["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted spec template #{resource_spec['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def find_resource_spec_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_resource_spec_by_id(val)
    else
      return find_resource_spec_by_name(val)
    end
  end

  def find_resource_spec_by_id(id)
    begin
      json_response = @resource_specs_interface.get(id.to_i)
      return json_response['specTemplate']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Spec Template not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_resource_spec_by_name(name)
    resource_specs = @resource_specs_interface.list({name: name.to_s})['specTemplates']
    if resource_specs.empty?
      print_red_alert "Spec Template not found by name #{name}"
      return nil
    elsif resource_specs.size > 1
      print_red_alert "#{resource_specs.size} spec templates found by name #{name}"
      print_resource_specs_table(resource_specs, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return resource_specs[0]
    end
  end

  def print_resource_specs_table(resource_specs, opts={})
    columns = [
      {"ID" => lambda {|resource_spec| resource_spec['id'] } },
      {"NAME" => lambda {|resource_spec| resource_spec['name'] } },
      #{"OWNER" => lambda {|resource_spec| resource_spec['account'] ? resource_spec['account']['name'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(resource_specs, columns, opts)
  end

  def format_resource_spec_type(val)
    val.to_s # .capitalize
  end

  def format_resource_spec_phase(val)
    val.to_s # .capitalize
  end

end
