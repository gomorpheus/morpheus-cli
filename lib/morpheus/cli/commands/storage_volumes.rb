require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageVolumes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageVolumesHelper

  set_command_name :'storage-volumes'
  set_command_description "View and manage storage volumes."
  register_subcommands %w{list get add remove}

  # RestCommand settings
  register_interfaces :storage_volumes, :storage_volume_types
  set_rest_has_type true

  protected

  def build_list_options(opts, options, params)
    opts.on('--storage-server VALUE', String, "Storage Server Name or ID") do |val|
      options[:storage_server] = val
    end
    opts.on('-t', '--type TYPE', "Filter by type") do |val|
      params['type'] = val
    end
    opts.on('--name VALUE', String, "Filter by name") do |val|
      params['name'] = val
    end
    opts.on('--category VALUE', String, "Filter by category") do |val|
      params['category'] = val
    end
    # build_standard_list_options(opts, options)
    super
  end

  def parse_list_options!(args, options, params)
    parse_parameter_as_resource_id!(:storage_server, options, params)
    super
  end

  def storage_volume_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Source" => lambda {|it| format_storage_volume_source(it) },
      "Storage" => lambda {|it| format_bytes(it['maxStorage']) },
      "Status" => lambda {|it| format_storage_volume_status(it) },
    }
  end

  def storage_volume_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : (it['account'] ? it['account']['name'] : nil) },
      "Cloud" => lambda {|it| it['zone']['name'] rescue '' },
      "Datastore" => lambda {|it| it['datastore']['name'] rescue '' },
      "Storage Group" => lambda {|it| it['storageGroup']['name'] rescue '' },
      "Storage Server" => lambda {|it| it['storageServer']['name'] rescue '' },
      "Source" => lambda {|it| format_storage_volume_source(it) },
      "Storage" => lambda {|it| format_bytes(it['maxStorage']) },
      "Status" => lambda {|it| format_storage_volume_status(it) },
    }
  end

  def add_storage_volume_option_types()
    [
      {'fieldContext' => 'storageServer', 'fieldName' => 'id', 'fieldLabel' => 'Storage Server', 'type' => 'select', 'optionSource' => 'storageServers', 'optionParams' => {'createType' => 'block'}, 'required' => true},
      {'fieldContext' => 'storageGroup', 'fieldName' => 'id', 'fieldLabel' => 'Storage Group', 'type' => 'select', 'optionSource' => 'storageGroups', 'required' => true},
      {'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Storage Volume Type', 'type' => 'select', 'optionSource' => 'storageVolumeTypes', 'required' => true},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
    ]
  end

  def update_storage_volume_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
    ]
  end

  def load_option_types_for_storage_volume(type_record, parent_record)
    storage_volume_type = type_record
    option_types = storage_volume_type['optionTypes']
    # ughhh, all this to change a label for API which uses bytes and not MB
    if option_types
      size_option_type = option_types.find {|it| it['fieldName'] == 'maxStorage' }
      if size_option_type
        #size_option_type['fieldLabel'] = "Volume Size (bytes)"
        size_option_type['fieldAddOn'] = "bytes"
      end
    end
    return option_types
  end

end
