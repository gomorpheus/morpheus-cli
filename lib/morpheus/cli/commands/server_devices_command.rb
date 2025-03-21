require 'morpheus/cli/cli_command'

class Morpheus::Cli::ServerDevicesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  # include Morpheus::Cli::OptionSourceHelper

  set_command_hidden # hide and prefer `hosts list-devices, get-device, assign-device. for now

  set_command_name :'host-devices'

  register_subcommands :list, :assign, :attach, :detach

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @servers_interface = @api_client.servers
    @server_devices_interface = @api_client.server_devices
  end

  def handle(args)
    handle_subcommand(args)
  end  

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} hosts [host] list-devices"
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List host devices.
[host] is required. This is the id of the host.
EOT
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:1)
    server_id = args[0] =~ /\A\d{1,}\Z/ ? args[0].to_i : find_server_by_name(args[0])['id']
    @server_devices_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @server_devices_interface.dry.list(server_id, params)
      return
    end
    json_response = @server_devices_interface.list(server_id, params)
    render_response(json_response, options, 'devices') do
      server_devices = json_response['devices']
      print_h1 "Host Devices: #{server_id}", parse_list_subtitles(options), options
      if server_devices.empty?
        print cyan,"No host devices found.",reset,"\n"
      else
        print as_pretty_table(server_devices, server_device_list_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
  end
  

  def assign(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} hosts assign [host] [device] [target]"
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Assign a host device to a target server.
[host] is required. This is the id of the host.
[device] is required. This is the id of the device.
[target] is required. This is the id of the target server.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:3)
    connect(options)
    server_id = args[0] =~ /\A\d{1,}\Z/ ? args[0].to_i : find_server_by_name(args[0])['id']
    device_id = args[1] ? args[1].to_i : nil
    if device_id.nil?
      avail_devices = @server_devices_interface.list(server_id)['devices'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
      device_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deviceId', 'fieldLabel' => 'Device', 'type' => 'select', 'selectOptions' => avail_devices, 'required' => true}], options[:options], @api_client)['deviceId']        
    end
    target_server_id = args[2] ? args[2].to_i : nil
    parse_payload(options) do |payload|
      if target_server_id.nil?
        # avail_servers = @servers_interface.list({max:10000, 'parentId' => server_id})['servers'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        # target_server_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetServerId', 'fieldLabel' => 'Target Server', 'type' => 'select', 'selectOptions' => avail_servers, 'required' => true}], options[:options], @api_client)['targetServerId']
        target_server_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetServerId', 'fieldLabel' => 'Target Server', 'type' => 'select', 'optionSource' => 'hostVms', 'required' => true}], options[:options], @api_client, {'parentId' => server_id})['targetServerId']
      end
      payload['targetServerId'] = target_server_id
    end
    execute_api(@server_devices_interface, :assign, [server_id, device_id], options) do |json_response|
      print_green_success "Assigned host device to target server"
    end
  end

  def attach(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} hosts attach [host] [device]"
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Attach a host device.
[host] is required. This is the id of the host.
[device] is required. This is the id of the device.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:3)
    connect(options)
    server_id = args[0] =~ /\A\d{1,}\Z/ ? args[0].to_i : find_server_by_name(args[0])['id']
    device_id = args[1] ? args[1].to_i : nil
    if device_id.nil?
      avail_devices = @server_devices_interface.list(server_id)['devices'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
      device_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deviceId', 'fieldLabel' => 'Device', 'type' => 'select', 'selectOptions' => avail_devices, 'required' => true}], options[:options], @api_client)['deviceId']        
    end
    parse_payload(options) do |payload|
      
    end
    execute_api(@server_devices_interface, :attach, [server_id, device_id], options) do |json_response|
      print_green_success "Attached host device"
    end
  end

  def detach(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} hosts detach [host] [device]"
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Detach a host device.
[host] is required. This is the id of the host.
[device] is required. This is the id of the device.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:3)
    connect(options)
    server_id = args[0] =~ /\A\d{1,}\Z/ ? args[0].to_i : find_server_by_name(args[0])['id']
    device_id = args[1] ? args[1].to_i : nil
    if device_id.nil?
      avail_devices = @server_devices_interface.list(server_id)['devices'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
      device_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deviceId', 'fieldLabel' => 'Device', 'type' => 'select', 'selectOptions' => avail_devices, 'required' => true}], options[:options], @api_client)['deviceId']        
    end
    parse_payload(options) do |payload|
      
    end
    execute_api(@server_devices_interface, :detach, [server_id, device_id], options) do |json_response|
      print_green_success "Detached host device"
    end
  end

  private

  # helper methods

  def server_device_list_column_definitions()
    # {
    #   "ID" => 'id',
    #   "Name" => 'name',
    #   "Ref" => lambda {|it| "#{it['refType']} #{it['refId']}" },
    #   "Type" => lambda {|it| it['type']['name'] rescue '' },
    #   "Status" => lambda {|it| format_server_device_status(it) },
    #   "External ID" => 'externalId',
    #   "Domain ID" => 'domainId',
    #   "Bus" => 'bus',
    #   "Slot" => 'slot',
    #   "Device" => 'device',
    #   "Vendor ID" => 'vendorId',
    #   "Product ID" => 'productId',
    #   "Function ID" => 'functionId',
    #   "Unique ID" => 'uniqueId',
    #   "IOMMU Group" => 'iommuGroup',
    #   "IOMMU Device Count" => 'iommuDeviceCount',
    # }
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type']['name'] rescue '' },
      "Bus" => 'bus',
      "Slot" => 'slot',
      "Status" => lambda {|it| format_server_device_status(it) },
      "Assignee" => lambda {|it| "#{it['refType']} #{it['refId']}" },
    }
  end

  def server_device_column_definitions()
    server_device_list_column_definitions()
  end

  def format_server_device_status(server_device, return_color=cyan)
    out = ""
    status_string = server_device['status'].to_s.upcase
    if status_string == 'ATTACHED' # || status_string == 'ASSIGNED'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == "PENDING"
      out <<  "#{yellow}#{status_string.upcase}#{return_color}"
    elsif status_string
      out <<  "#{cyan}#{status_string.upcase}#{return_color}"
    else
      out <<  ""
    end
    out
  end
  
end
