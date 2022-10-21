require 'morpheus/cli/cli_command'

class Morpheus::Cli::PluginsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :plugins
  set_command_description "View and manage security packages."
  register_subcommands :list, :get, :upload, :update, :remove, :'check-updates'

  # RestCommand settings
  register_interfaces :plugins

  def upload(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [file]")
      build_standard_post_options(opts, options)
      opts.footer = <<-EOT
Upload a plugin file.
[file] is required. This is the path of the .jar file to upload
This can be used to install and register a new plugin and also
to update an existing plugin to a new version.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    filename = args[0]
    filename = File.expand_path(filename)
    if !File.exists?(filename)
      raise_command_error "File not found: #{filename}"
    elsif !File.file?(filename)
      raise_command_error "File is a directory: #{filename}"
    end
    plugin_file = File.new(filename, 'rb')
    @plugins_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @plugins_interface.dry.upload(plugin_file)
      return
    end
    json_response = @plugins_interface.upload(plugin_file)
    render_response(json_response, options) do
      plugin = json_response[rest_object_key]
      print_green_success "Uploaded plugin #{plugin['name']} (#{plugin['version']})"
      # _get(plugin['id'], {}, options)
    end
    return 0, nil
  end

  def check_updates(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [file]")
      build_standard_post_options(opts, options)
      opts.footer = <<-EOT
Check for installed plugins that have available updates.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    params.merge!(parse_query_options(options))
    payload = parse_payload(options)
    @plugins_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @plugins_interface.dry.check_updates(payload, params)
      return
    end
    json_response = @plugins_interface.check_updates(payload, params)
    render_response(json_response, options) do
      plugins_to_update = json_response['pluginsToUpdate'] || []
      if plugins_to_update.size == 1
        print_green_success("1 plugin has an available update")
      else
        print_green_success("#{plugins_to_update.size} plugins have available updates")
      end
      if plugins_to_update.size > 0
        print_h2 "Plugins To Update", options
        puts as_pretty_table(plugins_to_update, [:id, :name])
      end
    end
    return 0, nil
  end

  protected

  def build_list_options(opts, options, params)
    opts.on('--name VALUE', String, "Filter by name") do |val|
      add_query_parameter(params, 'name', val)
    end
    opts.on('--code VALUE', String, "Filter by code") do |val|
      add_query_parameter(params, 'code', val)
    end
    opts.on('--version VALUE', String, "Filter by version") do |val|
      add_query_parameter(params, 'version', val)
    end
    opts.on('--status VALUE', String, "Filter by status") do |val|
      add_query_parameter(params, 'status', val)
    end
    opts.on('--enabled [true|false]', String, "Filter by enabled [true|false]") do |val|
      params['enabled'] = ['true','on','1',''].include?(val.to_s.downcase)
    end
    opts.on('--valid [true|false]', String, "Filter by valid [true|false]") do |val|
      params['valid'] = ['true','on','1',''].include?(val.to_s.downcase)
    end
    opts.on('--has-update [true|false]', String, "Filter by hasValidUpdate [true|false]") do |val|
      params['hasValidUpdate'] = ['true','on','1',''].include?(val.to_s.downcase)
    end
    super
  end

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      if record['statusMessage'].to_s != ''
        print_h2 "Status Message", options
        if record['status'].to_s.downcase == 'error'
          print red, record['statusMessage'], reset, "\n"
        else
          print record['statusMessage'], "\n"
        end
      end
      # Plugin Providers
      providers = record['providers']
      if providers && !providers.empty?
        print_h2 "Providers"
        print as_pretty_table(providers, [:name, :type], options)
      end
      # Plugin Configuration
      option_types = record["optionTypes"].sort {|a,b| a['displayOrder'].to_i <=> b['displayOrder'].to_i}
      config = record['config'] || {}
      if option_types && !option_types.empty?
        print_h2 "Configuration"
        rows = option_types.collect do |option_type|
          {:label => option_type['fieldLabel'], :name => option_type['fieldName'], :value => config[option_type['fieldName']]}
        end
        print as_pretty_table(rows, [:label, :name, :value], options)
      end
      print reset,"\n"
    end
  end

  def plugin_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      # "Code" => 'code',
      "Description" => 'description',
      "Version" => lambda {|it| it['version'] },
      "Enabled" => lambda {|it| format_boolean it['enabled'] },
      "Status" => lambda {|it| format_plugin_status(it) },
    }
  end

  def plugin_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
      "Version" => lambda {|it| it['version'] },
      "Author" => 'author',
      "Enabled" => lambda {|it| format_boolean it['enabled'] },
      "Valid" => lambda {|it| format_boolean it['valid'] },
      "Has Update?" => lambda {|it| format_boolean it['hasValidUpdate'] },
      "Status" => lambda {|it| format_plugin_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_plugin_option_types()
    [
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
    ]
  end

  def add_plugin_advanced_option_types()
    []
  end

  def update_plugin_option_types()
    option_types = add_plugin_option_types.collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
    option_types.reject! {|it| it['fieldName'] == 'type' }
    option_types
  end

  def update_plugin_advanced_option_types()
    add_plugin_advanced_option_types().collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
  end

  def format_plugin_status(plugin, return_color=cyan)
    out = ""
    status_string = plugin['status'].to_s.downcase
    if status_string == 'loaded'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'error'
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{plugin['statusMessage'] ? "#{return_color} - #{plugin['statusMessage']}" : ''}#{return_color}"
    else
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    end
    out
  end

end
