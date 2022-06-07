require 'morpheus/cli/cli_command'

class Morpheus::Cli::Thresholds
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :'scale-thresholds'
  set_command_description "View and manage scale thresholds."
  register_subcommands :list, :get, :add, :update, :remove

  # RestCommand settings
  register_interfaces :thresholds
  set_rest_interface_name :thresholds
  set_rest_name :threshold

  set_rest_label "Scale Threshold"
  set_rest_label_plural "Scale Thresholds"

  # def render_response_for_get(json_response, options)
  #   render_response(json_response, options, rest_object_key) do
  #     record = json_response[rest_object_key]
  #     print_h1 rest_label, [], options
  #     print cyan
  #     print_description_list(rest_column_definitions(options), record, options)
  #     # show Threshold Configuration
  #     config = record['config']
  #     if config && !config.empty?
  #       print_h2 "Configuration"
  #       print_description_list(config.keys, config)
  #     end
  #     print reset,"\n"
  #   end
  # end

  protected

  def threshold_object_key
    'threshold'
  end

  def threshold_list_key
    'thresholds'
  end

  def threshold_label
    'Threshold'
  end

  def threshold_label_plural
    'Threshold'
  end

  def threshold_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "CPU" => lambda {|it| it['cpuEnabled'] ? "✔" : '' },
      "Memory" => lambda {|it| it['memoryEnabled'] ? "✔" : '' },
      "Disk" => lambda {|it| it['diskEnabled'] ? "✔" : '' },
    }
  end

  def threshold_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Auto Upscale" => lambda {|it| format_boolean(it['autoUp']) },
      "Auto Downscale" => lambda {|it| format_boolean(it['autoDown']) },
      "Min Count" => lambda {|it| it['minCount'] },
      "Max Count" => lambda {|it| it['maxCount'] },
      "Enable CPU Threshold" => lambda {|it| format_boolean(it['cpuEnabled']) },
      "Min CPU" => lambda {|it| it['minCpu'] },
      "Max CPU" => lambda {|it| it['maxCpu'] },
      "Enable Memory Threshold" => lambda {|it| format_boolean(it['memoryEnabled']) },
      "Min Memory" => lambda {|it| it['minMemory'] },
      "Max Memory" => lambda {|it| it['maxMemory'] },
      "Enable Disk Threshold" => lambda {|it| format_boolean(it['diskEnabled']) },
      "Min Disk" => lambda {|it| it['minDisk'] },
      "Max Disk" => lambda {|it| it['maxDisk'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def add_threshold_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 10},
      {'fieldName' => 'autoUp', 'fieldLabel' => 'Auto Upscale', 'type' => 'checkbox', 'required' => true, 'defaultValue' => false, 'displayOrder' => 30},
      {'fieldName' => 'autoDown', 'fieldLabel' => 'Auto Downscale', 'type' => 'checkbox', 'required' => true, 'defaultValue' => false, 'displayOrder' => 40},
      {'fieldName' => 'minCount', 'fieldLabel' => 'Min Count', 'type' => 'number', 'required' => true, 'defaultValue' => 1, 'displayOrder' => 41},
      {'fieldName' => 'maxCount', 'fieldLabel' => 'Max Count', 'type' => 'number', 'required' => true, 'defaultValue' => 2, 'displayOrder' => 42},
      {'fieldName' => 'cpuEnabled', 'fieldLabel' => 'Enable CPU Threshold', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'displayOrder' => 50},
      {'fieldName' => 'minCpu', 'fieldLabel' => 'Min CPU', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 60},
      {'fieldName' => 'maxCpu', 'fieldLabel' => 'Max CPU', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 70},
      {'fieldName' => 'memoryEnabled', 'fieldLabel' => 'Enable Memory Threshold', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'displayOrder' => 80},
      {'fieldName' => 'minMemory', 'fieldLabel' => 'Min Memory', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 90},
      {'fieldName' => 'maxMemory', 'fieldLabel' => 'Max Memory', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 100},
      {'fieldName' => 'diskEnabled', 'fieldLabel' => 'Enable Disk Threshold', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'displayOrder' => 110},
      {'fieldName' => 'minDisk', 'fieldLabel' => 'Min Disk', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 120},
      {'fieldName' => 'maxDisk', 'fieldLabel' => 'Max Disk', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 130},
    ]
  end

  def add_threshold_advanced_option_types()
    []
  end

  def update_threshold_option_types()
    add_threshold_option_types.collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
  end

  def update_threshold_advanced_option_types()
    add_threshold_advanced_option_types.collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
  end

end
