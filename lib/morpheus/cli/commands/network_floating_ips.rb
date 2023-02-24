require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkFloatingIps
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :'network-floating-ips'
  set_command_description "View and manage network floating IPs."
  register_subcommands :list, :get, :release

  # RestCommand settings
  register_interfaces :network_floating_ips
  set_rest_has_name false
  set_rest_arg "id"

  def release(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Release an existing #{rest_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
Only the following cloud types support this command: OpenStack, Huawei and OpenTelekom
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id = args[0]
    record = rest_find_by_name_or_id(id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to release the #{rest_label.downcase} #{record['name'] || record['id']}?")
      return 9, "aborted"
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.release(record['id'], params)
      return 0, nil
    end
    json_response = rest_interface.release(record['id'], params)
    render_response(json_response, options) do
      print_green_success "Releasing #{rest_label.downcase} #{record['ipAddress'] || record['id']}"
    end
    return 0, nil
  end

  protected

  def build_list_options(opts, options, params)
    opts.on('--cloud CLOUD', String, "Cloud Name or ID") do |val|
      options[:cloud] = val
    end
    opts.on('--server SERVER', String, "Server Name or ID") do |val|
      options[:server] = val
    end
    opts.on('--vm VM', String, "Alias for --server") do |val|
      options[:server] = val
    end
    opts.add_hidden_option('--vm')
    opts.on('--ip-address VALUE', String, "Filter by IP Address") do |val|
      add_query_parameter(params, 'ipAddress', val)
    end
    opts.on('--status VALUE', String, "Filter by Status") do |val|
      add_query_parameter(params, 'ipStatus', val)
    end
    # build_standard_list_options(opts, options)
    super
  end

  def parse_list_options!(args, options, params)
    parse_parameter_as_resource_id!(:cloud, options, params, 'zoneId')
    parse_parameter_as_resource_id!(:server, options, params)
    super
  end

  def network_floating_ip_list_column_definitions(options)
    {
      "ID" => 'id',
      "IP Address" => 'ipAddress',
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
      "Status" => lambda {|it| it['ipStatus'].to_s.capitalize },
      "VM" => lambda {|it| it['server'] ? it['server']['name'] : '' },
    }
  end

  def network_floating_ip_column_definitions(options)
    {
      "ID" => 'id',
      "IP Address" => 'ipAddress',
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
      "Status" => lambda {|it| it['ipStatus'].to_s.capitalize },
      "VM" => lambda {|it| it['server'] ? it['server']['name'] : '' },
    }
  end

  def add_network_floating_ip_option_types()
    []
  end

  def update_network_floating_ip_option_types()
    []
  end

end
