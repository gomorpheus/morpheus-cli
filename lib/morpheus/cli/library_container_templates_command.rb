require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryContainerTemplatesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-file-templates'

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @container_templates_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).library_container_templates
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @container_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_templates_interface.dry.list(params)
        return
      end

      json_response = @container_templates_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "containerTemplates")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['containerTemplates'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containerTemplates")
        return 0
      end
      container_templates = json_response['containerTemplates']
      title = "Morpheus Library - File Templates"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if container_templates.empty?
        print cyan,"No container file templates found.",reset,"\n"
      else
        print_container_templates_table(container_templates, options)
        print_results_pagination(json_response, {:label => "container file template", :n_label => "container file templates"})
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

    begin
      container_template = find_container_template_by_name_or_id(id)
      if container_template.nil?
        return 1
      end
      @container_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_templates_interface.dry.get(container_template['id'])
        return
      end
      json_response = @container_templates_interface.get(container_template['id'])
      container_template = json_response['containerTemplate']
      instances = json_response['instances'] || []
      servers = json_response['servers'] || []
      if options[:json]
        puts as_json(json_response, options, "containerTemplate")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containerTemplate")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['containerTemplate']], options)
        return 0
      end

      print_h1 "File Template Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "File Name" => lambda {|it| it['fileName'] },
        "File Path" => lambda {|it| it['filePath'] },
        "Setting Category" => lambda {|it| it['settingCategory'] },
        "Setting Name" => lambda {|it| it['settingName'] },
        "Phase" => lambda {|it| it['templatePhase'] },
        "Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        # "Enabled" => lambda {|it| format_boolean it['enabled'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, container_template)

      print_h2 "Template"

      puts container_template['template']

      

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {'templatePhase' => 'provision'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--fileName VALUE', String, "File Name") do |val|
        params['fileName'] = val
      end
      opts.on('--filePath VALUE', String, "File Path") do |val|
        params['filePath'] = val
      end
      # opts.on('--code VALUE', String, "Code") do |val|
      #   params['code'] = val
      # end
      # opts.on('--description VALUE', String, "Description") do |val|
      #   params['description'] = val
      # end
      opts.on('--phase [start|stop|postProvision]', String, "Template Phase. Default is 'provision'") do |val|
        params['scriptPhase'] = val
      end
      opts.on('--category VALUE', String, "Category") do |val|
        params['category'] = val
      end
      # opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
      #   options['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      # end
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
        if !params['fileName']
          params['fileName'] = File.basename(full_filename)
        end
        # if !params['filePath']
        #   params['filePath'] = File.dirname(full_filename)
        # end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new file template." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    # support [name] as first argument
    if args[0]
      params['name'] = args[0]
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
        payload = {'containerTemplate' => params}
      end
      @container_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_templates_interface.dry.create(payload)
        return
      end
      json_response = @container_templates_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        container_template = json_response['containerTemplate']
        print_green_success "Added file template #{container_template['name']}"
        _get(container_template['id'], {})
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
      opts.on('--fileName VALUE', String, "File Name") do |val|
        params['fileName'] = val
      end
      opts.on('--filePath VALUE', String, "File Path") do |val|
        params['filePath'] = val
      end
      # opts.on('--code VALUE', String, "Code") do |val|
      #   params['code'] = val
      # end
      # opts.on('--description VALUE', String, "Description") do |val|
      #   params['description'] = val
      # end
      opts.on('--phase [start|stop]', String, "Template Phase") do |val|
        params['scriptPhase'] = val
      end

      # opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
      #   options['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      # end
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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a file template." + "\n" +
                    "[name] is required. This is the name or id of a file template."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      container_template = find_container_template_by_name_or_id(args[0])
      if container_template.nil?
        return 1
      end
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload = {'containerTemplate' => params}
      end
      @container_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_templates_interface.dry.update(container_template["id"], payload)
        return
      end
      json_response = @container_templates_interface.update(container_template["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated file template #{container_template['name']}"
        _get(container_template['id'], {})
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
      container_template = find_container_template_by_name_or_id(args[0])
      if container_template.nil?
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete file template '#{container_template['name']}'?", options)
        return false
      end

      # payload = {
      #   'containerTemplate' => {id: container_template["id"]}
      # }
      # payload['containerTemplate'].merge!(container_template)
      payload = params
      @container_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @container_templates_interface.dry.destroy(container_template["id"])
        return
      end

      json_response = @container_templates_interface.destroy(container_template["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted file template #{container_template['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def find_container_template_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_container_template_by_id(val)
    else
      return find_container_template_by_name(val)
    end
  end

  def find_container_template_by_id(id)
    begin
      json_response = @container_templates_interface.get(id.to_i)
      return json_response['containerTemplate']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "File Template not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_container_template_by_name(name)
    container_templates = @container_templates_interface.list({name: name.to_s})['containerTemplates']
    if container_templates.empty?
      print_red_alert "File Template not found by name #{name}"
      return nil
    elsif container_templates.size > 1
      print_red_alert "#{container_templates.size} file templates found by name #{name}"
      print_container_templates_table(container_templates, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return container_templates[0]
    end
  end

  def print_container_templates_table(container_templates, opts={})
    columns = [
      {"ID" => lambda {|container_template| container_template['id'] } },
      {"NAME" => lambda {|container_template| container_template['name'] } },
      {"FILE NAME" => lambda {|container_template| container_template['fileName'] } },
      {"FILE PATH" => lambda {|container_template| container_template['filePath'] } },
      {"SETTING CATEGORY" => lambda {|container_template| container_template['settingCategory'] } },
      {"SETTING NAME" => lambda {|container_template| container_template['settingName'] } },
      {"OWNER" => lambda {|container_template| container_template['account'] ? container_template['account']['name'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(container_templates, columns, opts)
  end


end
