require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibrarySpecTemplatesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper
  set_command_name :'library-spec-templates'
  register_subcommands :list, :get, :add, :update, :remove, :list_types
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @spec_templates_interface = @api_client.library_spec_templates
    @spec_template_types_interface = @api_client.library_spec_template_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List spec templates."
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
      @spec_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @spec_templates_interface.dry.list(params)
        return
      end
      # do it
      json_response = @spec_templates_interface.list(params)
      render_result = render_with_format(json_response, options, 'specTemplates')
      return 0 if render_result
      resource_specs = json_response['specTemplates']
      title = "Morpheus Library - Spec Templates"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if resource_specs.empty?
        print cyan,"No spec templates found.",reset,"\n"
      else
        # print_resource_specs_table(resource_specs, options)
        columns = [
          {"ID" => lambda {|resource_spec| resource_spec['id'] } },
          {"NAME" => lambda {|resource_spec| resource_spec['name'] } },
          {"LABELS" => lambda {|it| format_list(it['labels'], '', 3) rescue '' }},
          {"TYPE" => lambda {|resource_spec| resource_spec['type']['name'] rescue '' } },
          {"SOURCE" => lambda {|resource_spec| resource_spec['file']['sourceType'] rescue '' } },
          {"CREATED" => lambda {|resource_spec| format_local_dt(resource_spec['dateCreated']) } },
        ]
        print as_pretty_table(resource_specs, columns, options)
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
      opts.on('--no-content', "Do not display content." ) do
        options[:no_content] = true
      end
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
      resource_spec = find_spec_template_by_name_or_id(id)
      if resource_spec.nil?
        return 1
      end
      @spec_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @spec_templates_interface.dry.get(resource_spec['id'])
        return
      end
      json_response = @spec_templates_interface.get(resource_spec['id'])
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

      print_h1 "Spec Template Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Labels" => lambda {|it| format_list(it['labels'], '', 3) rescue '' },
        "Type" => lambda {|it| it['type']['name'] rescue '' },
        "Source" => lambda {|it| it['file']['sourceType'] rescue '' },
        #"Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Created By" => lambda {|it| it['createdBy'] },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        "Updated By" => lambda {|it| it['updatedBy'] },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) + " by #{it['createdBy']}" },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) + " by #{it['updatedBy'] || it['createdBy']}" },
      }
      template_type = resource_spec['type']['code'] rescue nil
      if template_type.to_s.downcase == 'cloudformation'
        cloudformation_description_cols = {
          "CAPABILITY_IAM" => lambda {|it| format_boolean(it['config']['cloudformation']['IAM']) rescue '' },
          "CAPABILITY_NAMED_IAM" => lambda {|it| format_boolean(it['config']['cloudformation']['CAPABILITY_NAMED_IAM']) rescue '' },
          "CAPABILITY_AUTO_EXPAND" => lambda {|it| format_boolean(it['config']['cloudformation']['CAPABILITY_AUTO_EXPAND']) rescue '' },
        }
        description_cols.merge!(cloudformation_description_cols)
      end
      print_description_list(description_cols, resource_spec)

      unless options[:no_content]
        file_content = resource_spec['file']
        print_h2 "Content"
        if file_content
          if file_content['sourceType'] == 'local'
            puts file_content['content']
          elsif file_content['sourceType'] == 'url'
            puts "URL: #{file_content['contentPath']}"
          elsif file_content['sourceType'] == 'repository'
            puts "Repository: #{file_content['repository']['name'] rescue 'n/a'}"
            puts "Path: #{file_content['contentPath']}"
            if file_content['contentRef']
              puts "Ref: #{file_content['contentRef']}"
            end
          else
            puts "Source: #{file_content['sourceType']}"
            puts "Path: #{file_content['contentPath']}"
          end
        else
          print cyan,"No file content.",reset,"\n"
        end
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    file_params = {}
    template_type = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        params['labels'] = parse_labels(val)
      end
      opts.on('-t', '--type TYPE', "Spec Template Type. i.e. arm, cloudFormation, helm, kubernetes, oneview, terraform, ucs") do |val|
        template_type = val.to_s
      end
      opts.on('--source VALUE', String, "Source Type. local, repository, url") do |val|
        file_params['sourceType'] = val
      end
      opts.on('--content TEXT', String, "Contents of the template. This implies source is local.") do |val|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        file_params['content'] = val
      end
      opts.on('--file FILE', "File containing the template. This can be used instead of --content" ) do |filename|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          file_params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
        # use the filename as the name by default.
        if !params['name']
          params['name'] = File.basename(full_filename)
        end
      end
      opts.on('--url VALUE', String, "URL, for use when source is url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-path VALUE', String, "Content Path, for use when source is repository or url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-ref VALUE', String, "Content Ref (Version Ref), for use when source is repository") do |val|
        file_params['contentRef'] = val
      end
      # opts.on('--enabled [on|off]', String, "Can be used to disable it") do |val|
      #   options['enabled'] = !(val.to_s == 'off' || val.to_s == 'false')
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new spec template."
    end
    optparse.parse!(args)
    # support [name] as first argument
    if args[0]
      params['name'] = args[0]
    end
    connect(options)
    begin
      # construct payload
      payload = nil
      passed_options = options[:options].reject {|k,v| k.is_a?(Symbol) }
      if options[:payload]
        payload = options[:payload]
        # merge -O options into normally parsed options
        params['file'] = file_params unless file_params.empty?
        unless params.empty?
          payload.deep_merge!({'specTemplate' => params })
        end
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # prompt
        if params['name'].nil?
          params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options], @api_client,{})['name']
        end
        if template_type.nil?
          # use code instead of id
          #template_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => 'resourceSpecType', 'required' => true}], options[:options], @api_client,{})['type']
          #params['type'] = {'id' => template_type}
          spec_type_dropdown = get_all_spec_template_types.collect { |it| {'value' => it['code'], 'name' => it['name']} }
          template_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => spec_type_dropdown, 'required' => true}], options[:options], @api_client,{})['type']
          params['type'] = {'code' => template_type}
        else
          # gotta look up id
          template_type_obj = find_spec_template_type_by_name_or_code_id(template_type)
          return 1 if template_type_obj.nil?
          template_type = template_type_obj['code']
          params['type'] = {'code' => template_type}
        end
        
        # file content
        options[:options]['file'] ||= {}
        options[:options]['file'].merge!(file_params)
        file_params = Morpheus::Cli::OptionTypes.file_content_prompt({'fieldName' => 'file', 'fieldLabel' => 'File Content', 'type' => 'file-content', 'required' => true}, options[:options], @api_client, {})

        # if source_type.nil?
        #   source_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'source', 'fieldLabel' => 'Source', 'type' => 'select', 'optionSource' => 'fileContentSource', 'required' => true, 'defaultValue' => 'local'}], options[:options], @api_client,{})['source']
        #   file_params['sourceType'] = source_type
        # end
        # # source type options
        # if source_type == "local"
        #   # prompt for content
        #   if file_params['content'].nil?
        #     file_params['content'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'content', 'type' => 'code-editor', 'fieldLabel' => 'Content', 'required' => true, 'description' => 'The file content'}], options[:options])['content']
        #   end
        # elsif source_type == "url"
        #   if file_params['contentPath'].nil?
        #     file_params['contentPath'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'url', 'fieldLabel' => 'URL', 'type' => 'text', 'required' => true}], options[:options], @api_client,{})['url']
        #   end
        # elsif source_type == "repository"
        #   if file_params['repository'].nil?
        #     repository_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'repositoryId', 'fieldLabel' => 'Repository', 'type' => 'select', 'optionSource' => 'codeRepositories', 'required' => true}], options[:options], @api_client,{})['repositoryId']
        #     file_params['repository'] = {'id' => repository_id}
        #   end
        #   if file_params['contentPath'].nil?
        #     file_params['contentPath'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'path', 'fieldLabel' => 'File Path', 'type' => 'text', 'required' => true}], options[:options], @api_client,{})['path']
        #   end
        #   if file_params['contentRef'].nil?
        #     file_params['contentRef'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ref', 'fieldLabel' => 'Version Ref', 'type' => 'text'}], options[:options], @api_client,{})['ref']
        #   end
        # end
        # config
        if template_type.to_s.downcase == "cloudformation"
          # JD: the field names the UI uses are inconsistent, should fix in api...
          cloud_formation_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'cloudformation.IAM', 'fieldLabel' => 'CAPABILITY_IAM', 'type' => 'checkbox'},
            {'fieldContext' => 'config', 'fieldName' => 'cloudformation.CAPABILITY_NAMED_IAM', 'fieldLabel' => 'CAPABILITY_NAMED_IAM', 'type' => 'checkbox'},
            {'fieldContext' => 'config', 'fieldName' => 'cloudformation.CAPABILITY_AUTO_EXPAND', 'fieldLabel' => 'CAPABILITY_AUTO_EXPAND', 'type' => 'checkbox'}
          ]
          v_prompt = Morpheus::Cli::OptionTypes.prompt(cloud_formation_option_types, options[:options], @api_client,{})
          params.deep_merge!(v_prompt)
        end
        params['file'] = file_params
        payload = {'specTemplate' => params}
      end
      @spec_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @spec_templates_interface.dry.create(payload)
        return
      end
      json_response = @spec_templates_interface.create(payload)
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
    file_params = {}
    template_type = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        params['labels'] = parse_labels(val)
      end
      opts.on('-t', '--type TYPE', "Spec Template Type. kubernetes, helm, terraform, cloudFormation") do |val|
        template_type = val.to_s
      end
      opts.on('--source VALUE', String, "Source Type. local, repository, url") do |val|
        file_params['sourceType'] = val
      end
      opts.on('--content TEXT', String, "Contents of the template. This implies source is local.") do |val|
        # file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        file_params['content'] = val
      end
      opts.on('--file FILE', "File containing the template. This can be used instead of --content" ) do |filename|
        file_params['sourceType'] = 'local' if file_params['sourceType'].nil?
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          file_params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on('--url VALUE', String, "File URL, for use when source is url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-path VALUE', String, "Content Path, for use when source is repository or url") do |val|
        file_params['contentPath'] = val
      end
      opts.on('--content-ref VALUE', String, "Content Ref (Version Ref), for use when source is repository") do |val|
        file_params['contentRef'] = val
      end
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
      resource_spec = find_spec_template_by_name_or_id(args[0])
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
        if params.empty? && file_params.empty?
          print_red_alert "Specify at least one option to update"
          puts optparse
          return 1
        end
        # massage special params
        if !template_type.nil?
          # gotta look up id
          template_type_obj = find_spec_template_type_by_name_or_code_id(template_type)
          return 1 if template_type_obj.nil?
          template_type = template_type_obj['code']
          params['type'] = {'code' => template_type}
        end
        if !file_params.empty?
          params['file'] = file_params
        end
        payload = {'specTemplate' => params}
      end
      @spec_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @spec_templates_interface.dry.update(resource_spec["id"], payload)
        return
      end
      json_response = @spec_templates_interface.update(resource_spec["id"], payload)
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
      resource_spec = find_spec_template_by_name_or_id(args[0])
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
      @spec_templates_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @spec_templates_interface.dry.destroy(resource_spec["id"])
        return
      end

      json_response = @spec_templates_interface.destroy(resource_spec["id"])
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

  def list_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List spec template types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @spec_template_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @spec_template_types_interface.dry.list(params)
        return
      end
      json_response = @spec_template_types_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'specTemplateTypes')
      return 0 if render_result

      spec_template_types = json_response['specTemplateTypes']

      title = "Morpheus Spec Template Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if spec_template_types.empty?
        print cyan,"No spec template types found.",reset,"\n"
      else
        rows = spec_template_types.collect do |spec_template_type|
          {
            id: spec_template_type['id'],
            code: spec_template_type['code'],
            name: spec_template_type['name']
          }
        end
        columns = [:id, :name, :code]
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  

end
