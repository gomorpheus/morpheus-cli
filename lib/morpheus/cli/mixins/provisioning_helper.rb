require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
# Mixin for Morpheus::Cli command classes 
# Provides common methods for provisioning instances
module Morpheus::Cli::ProvisioningHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  # This recreates the behavior of multi_disk.js
  # returns array of volumes based on service plan options (plan_info)
  def prompt_volumes(plan_info, options={}, api_client=nil, api_params={})
    #puts "Configure Volumes:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))

    volumes = []

    plan_size = nil
    if plan_info['maxStorage']
      plan_size = plan_info['maxStorage'].to_i / (1024 * 1024 * 1024)
    end

    root_storage_types = []
    if plan_info['rootStorageTypes']
      plan_info['rootStorageTypes'].each do |opt|
        if !opt.nil?
          root_storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    storage_types = []
    if plan_info['storageTypes']
      plan_info['storageTypes'].each do |opt|
        if !opt.nil?
          storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    datastore_options = []
    if plan_info['supportsAutoDatastore']
      if plan_info['autoOptions']
        plan_info['autoOptions'].each do |opt|
          if !opt.nil?
            datastore_options << {'name' => opt['name'], 'value' => opt['id']}
          end
        end
      end
    end
    if plan_info['datastores']
      plan_info['datastores'].each do |k, v|
        v.each do |opt|
          if !opt.nil?
            datastore_options << {'name' => "#{k}: #{opt['name']}", 'value' => opt['id']}
          end
        end
      end
    end

    #puts "Configure Root Volume"

    field_context = "rootVolume"

    if root_storage_types.empty?
      # this means there's no configuration, just send a single root volume to the server
      storage_type_id = nil
      storage_type = nil
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => 'Root Storage Type', 'selectOptions' => root_storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
      storage_type_id = v_prompt[field_context]['storageType']
      storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
    end

    # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
    root_custom_size_options = []
    if plan_info['rootCustomSizeOptions'] && plan_info['rootCustomSizeOptions'][storage_type_id.to_s]
      plan_info['rootCustomSizeOptions'][storage_type_id.to_s].each do |opt|
        if !opt.nil?
          root_custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
        end
      end
    end

    volume_label = 'root'
    volume = {
      'id' => -1, 
      'rootVolume' => true,
      'name' => volume_label,
      'size' => plan_size,
      'sizeId' => nil,
      'storageType' => storage_type_id,
      'datastoreId' => nil
    }

    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customLabel']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Root Volume Label', 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume_label}], options[:options])
      volume['name'] = v_prompt[field_context]['name']
    end
    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customSize']
      if root_custom_size_options.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => 'Root Volume Size (GB)', 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => plan_size}], options[:options])
        volume['size'] = v_prompt[field_context]['size']
        volume['sizeId'] = nil #volume.delete('sizeId')
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => 'Root Volume Size', 'selectOptions' => root_custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
        volume['sizeId'] = v_prompt[field_context]['sizeId']
        volume['size'] = nil #volume.delete('size')
      end
    else
      # might need different logic here ? =o
      volume['size'] = plan_size 
      volume['sizeId'] = nil #volume.delete('sizeId')
    end
    if !datastore_options.empty?
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => 'Root Datastore', 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
      volume['datastoreId'] = v_prompt[field_context]['datastoreId']
    end

    volumes << volume

    if plan_info['addVolumes']
      volume_index = 1
      
      has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
      add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add data volume?"))
      
      while add_another_volume do
        
        #puts "Configure Data #{volume_index} Volume"

        field_context = "dataVolume#{volume_index}"

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Type", 'selectOptions' => storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
        storage_type_id = v_prompt[field_context]['storageType']
        storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
        

        # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
        custom_size_options = []
        if plan_info['customSizeOptions'] && plan_info['customSizeOptions'][storage_type_id.to_s]
          plan_info['customSizeOptions'][storage_type_id.to_s].each do |opt|
            if !opt.nil?
              custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
            end
          end
        end

        volume_label = (volume_index == 1 ? 'data' : "data #{volume_index}")
        volume = {
          'id' => -1, 
          'rootVolume' => false,
          'name' => volume_label,
          'size' => plan_size,
          'sizeId' => nil,
          'storageType' => storage_type_id,
          'datastoreId' => nil
        }

        if plan_info['customizeVolume'] && storage_type['customLabel']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "Disk #{volume_index} Volume Label", 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume_label}], options[:options])
          volume['name'] = v_prompt[field_context]['name']
        end
        if plan_info['customizeVolume'] && storage_type['customSize']
          if custom_size_options.empty?
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Disk #{volume_index} Volume Size (GB)", 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => plan_size}], options[:options])
            volume['size'] = v_prompt[field_context]['size']
            volume['sizeId'] = nil #volume.delete('sizeId')
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Volume Size", 'selectOptions' => custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
            volume['sizeId'] = v_prompt[field_context]['sizeId']
            volume['size'] = nil #volume.delete('size')
          end
        else
          # might need different logic here ? =o
          volume['size'] = plan_size 
          volume['sizeId'] = nil #volume.delete('sizeId')
        end
        if !datastore_options.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Datastore", 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
          volume['datastoreId'] = v_prompt[field_context]['datastoreId']
        end

        volumes << volume

        # todo: should maxDisk check consider the root volume too?
        if plan_info['maxDisk'] && volume_index >= plan_info['maxDisk']
          add_another_volume = false
        else
          volume_index += 1
          has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
          add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another data volume?"))
        end

      end

    end

    return volumes
  end


  # This recreates the behavior of multi_disk.js
  # returns array of volumes based on service plan options (plan_info)
  def prompt_resize_volumes(current_volumes, plan_info, options={}, api_client=nil, api_params={})
    #puts "Configure Volumes:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))

    current_root_volume = current_volumes[0]

    volumes = []

    plan_size = nil
    if plan_info['maxStorage']
      plan_size = plan_info['maxStorage'].to_i / (1024 * 1024 * 1024)
    end

    root_storage_types = []
    if plan_info['rootStorageTypes']
      plan_info['rootStorageTypes'].each do |opt|
        if !opt.nil?
          root_storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    storage_types = []
    if plan_info['storageTypes']
      plan_info['storageTypes'].each do |opt|
        if !opt.nil?
          storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    datastore_options = []
    if plan_info['supportsAutoDatastore']
      if plan_info['autoOptions']
        plan_info['autoOptions'].each do |opt|
          if !opt.nil?
            datastore_options << {'name' => opt['name'], 'value' => opt['id']}
          end
        end
      end
    end
    if plan_info['datastores']
      plan_info['datastores'].each do |k, v|
        v.each do |opt|
          if !opt.nil?
            datastore_options << {'name' => "#{k}: #{opt['name']}", 'value' => opt['id']}
          end
        end
      end
    end

    #puts "Configure Root Volume"

    field_context = "rootVolume"

    if root_storage_types.empty?
      # this means there's no configuration, just send a single root volume to the server
      storage_type_id = nil
      storage_type = nil
    else
      #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => 'Root Storage Type', 'selectOptions' => root_storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
      #storage_type_id = v_prompt[field_context]['storageType']
      storage_type_id = current_root_volume['type'] || current_root_volume['storageType']
      storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
    end

    # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
    root_custom_size_options = []
    if plan_info['rootCustomSizeOptions'] && plan_info['rootCustomSizeOptions'][storage_type_id.to_s]
      plan_info['rootCustomSizeOptions'][storage_type_id.to_s].each do |opt|
        if !opt.nil?
          root_custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
        end
      end
    end

    volume = {
      'id' => current_root_volume['id'], 
      'rootVolume' => true,
      'name' => current_root_volume['name'],
      'size' => current_root_volume['size'] > plan_size ? current_root_volume['size'] : plan_size,
      'sizeId' => nil,
      'storageType' => storage_type_id,
      'datastoreId' => current_root_volume['datastoreId']
    }

    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customLabel']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Root Volume Label', 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume['name']}], options[:options])
      volume['name'] = v_prompt[field_context]['name']
    end
    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customSize']
      if root_custom_size_options.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => 'Root Volume Size (GB)', 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
        volume['size'] = v_prompt[field_context]['size']
        volume['sizeId'] = nil #volume.delete('sizeId')
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => 'Root Volume Size', 'selectOptions' => root_custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
        volume['sizeId'] = v_prompt[field_context]['sizeId']
        volume['size'] = nil #volume.delete('size')
      end
    else
      # might need different logic here ? =o
      volume['size'] = plan_size 
      volume['sizeId'] = nil #volume.delete('sizeId')
    end
    # if !datastore_options.empty?
    #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => 'Root Datastore', 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
    #   volume['datastoreId'] = v_prompt[field_context]['datastoreId']
    # end

    volumes << volume

    # modify or delete existing data volumes
    (1..(current_volumes.size-1)).each do |volume_index|
      current_volume = current_volumes[volume_index]
      
      if current_volume

        field_context = "dataVolume#{volume_index}"

        if no_prompt
          volume_action = 'keep'
        else
          action_options = [{'name' => 'Modify', 'value' => 'modify'}, {'name' => 'Keep', 'value' => 'keep'}, {'name' => 'Delete', 'value' => 'delete'}]
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'action', 'type' => 'select', 'fieldLabel' => "Modify/Keep/Delete volume '#{current_volume['name']}'", 'selectOptions' => action_options, 'required' => true, 'description' => 'Modify, Keep or Delete existing data volume?'}], options[:options])
          volume_action = v_prompt[field_context]['action']
        end

        if volume_action == 'delete'
          # deleted volume is just excluded from post params
          next
        elsif volume_action == 'keep'
          volume = {
            'id' => current_volume['id'].to_i, 
            'rootVolume' => false,
            'name' => current_volume['name'],
            'size' => current_volume['size'] > plan_size ? current_volume['size'] : plan_size,
            'sizeId' => nil,
            'storageType' => (current_volume['type'] || current_volume['storageType']),
            'datastoreId' => current_volume['datastoreId']
          }
          volumes << volume
        else
        
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Type", 'selectOptions' => storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
          # storage_type_id = v_prompt[field_context]['storageType']
          storage_type_id = current_volume['type'] || current_volume['storageType']
          storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
          
          # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
          custom_size_options = []
          if plan_info['customSizeOptions'] && plan_info['customSizeOptions'][storage_type_id.to_s]
            plan_info['customSizeOptions'][storage_type_id.to_s].each do |opt|
              if !opt.nil?
                custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
              end
            end
          end

          volume = {
            'id' => current_volume['id'].to_i, 
            'rootVolume' => false,
            'name' => current_volume['name'],
            'size' => current_volume['size'] > plan_size ? current_volume['size'] : plan_size,
            'sizeId' => nil,
            'storageType' => (current_volume['type'] || current_volume['storageType']),
            'datastoreId' => current_volume['datastoreId']
          }

          if plan_info['customizeVolume'] && storage_type['customLabel']
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "Disk #{volume_index} Volume Label", 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume['name']}], options[:options])
            volume['name'] = v_prompt[field_context]['name']
          end
          if plan_info['customizeVolume'] && storage_type['customSize']
            if custom_size_options.empty?
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Disk #{volume_index} Volume Size (GB)", 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
              volume['size'] = v_prompt[field_context]['size']
              volume['sizeId'] = nil #volume.delete('sizeId')
            else
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Volume Size", 'selectOptions' => custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
              volume['sizeId'] = v_prompt[field_context]['sizeId']
              volume['size'] = nil #volume.delete('size')
            end
          else
            # might need different logic here ? =o
            volume['size'] = plan_size 
            volume['sizeId'] = nil #volume.delete('sizeId')
          end
          # if !datastore_options.empty?
          #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Datastore", 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
          #   volume['datastoreId'] = v_prompt[field_context]['datastoreId']
          # end

          volumes << volume

        end

      end
    end


    if plan_info['addVolumes']
      volume_index = current_volumes.size
      
      has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
      add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add data volume?"))
      
      while add_another_volume do
        
        #puts "Configure Data #{volume_index} Volume"

        field_context = "dataVolume#{volume_index}"

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Type", 'selectOptions' => storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
        storage_type_id = v_prompt[field_context]['storageType']
        storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
        

        # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
        custom_size_options = []
        if plan_info['customSizeOptions'] && plan_info['customSizeOptions'][storage_type_id.to_s]
          plan_info['customSizeOptions'][storage_type_id.to_s].each do |opt|
            if !opt.nil?
              custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
            end
          end
        end

        volume_label = (volume_index == 1 ? 'data' : "data #{volume_index}")
        volume = {
          'id' => -1, 
          'rootVolume' => false,
          'name' => volume_label,
          'size' => plan_size,
          'sizeId' => nil,
          'storageType' => storage_type_id,
          'datastoreId' => nil
        }

        if plan_info['customizeVolume'] && storage_type['customLabel']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "Disk #{volume_index} Volume Label", 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume_label}], options[:options])
          volume['name'] = v_prompt[field_context]['name']
        end
        if plan_info['customizeVolume'] && storage_type['customSize']
          if custom_size_options.empty?
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Disk #{volume_index} Volume Size (GB)", 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => plan_size}], options[:options])
            volume['size'] = v_prompt[field_context]['size']
            volume['sizeId'] = nil #volume.delete('sizeId')
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Volume Size", 'selectOptions' => custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
            volume['sizeId'] = v_prompt[field_context]['sizeId']
            volume['size'] = nil #volume.delete('size')
          end
        else
          # might need different logic here ? =o
          volume['size'] = plan_size 
          volume['sizeId'] = nil #volume.delete('sizeId')
        end
        if !datastore_options.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Datastore", 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
          volume['datastoreId'] = v_prompt[field_context]['datastoreId']
        end

        volumes << volume

        # todo: should maxDisk check consider the root volume too?
        if plan_info['maxDisk'] && volume_index >= plan_info['maxDisk']
          add_another_volume = false
        else
          volume_index += 1
          has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
          add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another data volume?"))
        end

      end

    end

    return volumes
  end


  # This recreates the behavior of multi_networks.js
  # This is used by both `instances add` and `hosts add`
  # returns array of networkInterfaces based on provision type and cloud settings
  def prompt_network_interfaces(zone_id, provision_type_id, options={}, api_client=nil)
    #puts "Configure Networks:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    
    network_interfaces = []

    zone_network_options_json = api_client.options.options_for_source('zoneNetworkOptions', {zoneId: zone_id, provisionTypeId: provision_type_id})
    # puts "zoneNetworkOptions JSON"
    # puts JSON.pretty_generate(zone_network_options_json)    
    zone_network_data = zone_network_options_json['data'] || {}
    networks = zone_network_data['networks']
    network_interface_types = (zone_network_data['networkTypes'] || []).sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
    enable_network_type_selection = (zone_network_data['enableNetworkTypeSelection'] == 'on' || zone_network_data['enableNetworkTypeSelection'] == true)
    has_networks = zone_network_data["hasNetworks"] == true
    max_networks = zone_network_data["maxNetworks"] ? zone_network_data["maxNetworks"].to_i : nil

    # skip unless provision type supports networks
    if !has_networks
      return nil
    end

    # no networks available, shouldn't happen
    if networks.empty?
      return network_interfaces
    end

    network_options = []
    networks.each do |opt|
      if !opt.nil?
        network_options << {'name' => opt['name'], 'value' => opt['id']}
      end
    end

    network_interface_type_options = []
    network_interface_types.each do |opt|
      if !opt.nil?
        network_interface_type_options << {'name' => opt['name'], 'value' => opt['id']}
      end
    end


    interface_index = 1
    
    # has_another_interface = options[:options] && options[:options]["networkInterface"]
    # add_another_interface = has_another_interface || (!no_prompt)
    add_another_interface = true
    
    while add_another_interface do
      
      # if !no_prompt
      #   if interface_index == 1
      #     puts "Configure Network Interface"
      #   else
      #     puts "Configure Network Interface #{interface_index}"
      #   end
      # end

      field_context = interface_index == 1 ? "networkInterface" : "networkInterface#{interface_index}"
      
      network_interface = {}

      # choose network
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'networkId', 'type' => 'select', 'fieldLabel' => "Network", 'selectOptions' => network_options, 'required' => true, 'skipSingleOption' => false, 'description' => 'Choose a network for this interface.', 'defaultValue' => network_interface['networkId']}], options[:options])
      network_interface['network'] = {}
      network_interface['network']['id'] = v_prompt[field_context]['networkId'].to_i

      selected_network = networks.find {|it| it["id"] == network_interface['network']['id'] }

      # choose network interface type
      if enable_network_type_selection && !network_interface_type_options.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'networkInterfaceTypeId', 'type' => 'select', 'fieldLabel' => "Network Interface Type", 'selectOptions' => network_interface_type_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a network interface type.', 'defaultValue' => network_interface['networkInterfaceTypeId']}], options[:options])
        network_interface['networkInterfaceTypeId'] = v_prompt[field_context]['networkInterfaceTypeId'].to_i
      end

      # choose IP unless network has a pool configured
      if selected_network['pool']
        puts "IP Address: Using pool '#{selected_network['pool']['name']}'" if !no_prompt
      elsif selected_network['dhcpServer']
        puts "IP Address: Using DHCP" if !no_prompt
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'ipAddress', 'type' => 'text', 'fieldLabel' => "IP Address", 'required' => true, 'description' => 'Enter an IP for this network interface. x.x.x.x', 'defaultValue' => network_interface['ipAddress']}], options[:options])
        network_interface['ipAddress'] = v_prompt[field_context]['ipAddress']
      end
      
      network_interfaces << network_interface
      
      interface_index += 1
      has_another_interface = options[:options] && options[:options]["networkInterface#{interface_index}"]
      add_another_interface = has_another_interface || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another network interface?"))
      if max_networks && network_interfaces.size >= max_networks
        add_another_interface = false
      end

    end

    return network_interfaces

  end

  # reject old volume option types
  # these will eventually get removed from the associated optionTypes
  def reject_volume_option_types(option_types)
    option_types.reject {|opt| 
        ['osDiskSize', 'osDiskType',
          'diskSize', 'diskType',
          'datastoreId', 'storagePodId'
        ].include?(opt['fieldName'])
      }
  end

  # reject old networking option types
  # these will eventually get removed from the associated optionTypes
  def reject_networking_option_types(option_types)
    option_types.reject {|opt| 
        ['networkId', 'networkType', 'ipAddress', 'netmask', 'gateway', 'nameservers',
          'vmwareNetworkType', 'vmwareIpAddress', 'vmwareNetmask', 'vmwareGateway', 'vmwareNameservers'
        ].include?(opt['fieldName'])
      }
  end

end
