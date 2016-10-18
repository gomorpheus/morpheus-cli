require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
# Mixin for Morpheus::Cli command classes 
# Provides common methods for provisioning instances
module Morpheus::Cli::ProvisioningHelper

  def self.included(klass)
    klass.include Morpheus::Cli::PrintHelper
  end

  # This recreates the behavior of multi_disk.js
  # returns array of volumes based on service plan options (plan_info)
  def prompt_instance_volumes(plan_info, options={}, api_client=nil, api_params={})
    #puts "Configure Volumes:"
    volumes = []

    plan_size = nil
    if plan_info['maxStorage']
      plan_size = plan_info['maxStorage'].to_i / (1024 * 1024 * 1024)
    end

    root_storage_types = []
    if plan_info['rootStorageTypes']
      plan_info['rootStorageTypes'].each do |opt|
        root_storage_types << {'name' => opt['name'], 'value' => opt['id']}
      end
    end

    storage_types = []
    if plan_info['storageTypes']
      plan_info['storageTypes'].each do |opt|
        storage_types << {'name' => opt['name'], 'value' => opt['id']}
      end
    end

    datastore_options = []
    if plan_info['supportsAutoDatastore']
      if plan_info['autoOptions']
        plan_info['autoOptions'].each do |opt|
          datastore_options << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end
    if plan_info['datastores']
      plan_info['datastores'].each do |k, v|
        v.each do |opt|
          datastore_options << {'name' => "#{k}: #{opt['name']}", 'value' => opt['id']}
        end
      end
    end

    #puts "Configure Root Volume"

    field_context = "rootVolume"

    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => 'Root Storage Type', 'selectOptions' => root_storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
    storage_type_id = v_prompt[field_context]['storageType']
    storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }

    # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
    root_custom_size_options = []
    if plan_info['rootCustomSizeOptions'] && plan_info['rootCustomSizeOptions'][storage_type_id.to_s]
      plan_info['rootCustomSizeOptions'][storage_type_id.to_s].each do |opt|
        root_custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
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

    if plan_info['rootDiskCustomizable'] && storage_type['customLabel']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Root Volume Label', 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume_label}], options[:options])
      volume['name'] = v_prompt[field_context]['name']
    end
    if plan_info['rootDiskCustomizable'] && storage_type['customSize']
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

    if plan_info['addVolumes'] && !options[:skip_option_prompts]
      volume_index = 1
      add_another_volume = (options[:options] && options[:options]["dataVolume#{volume_index}"]) || Morpheus::Cli::OptionTypes.confirm("Add data volume?")
      
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
            custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
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
          add_another_volume = (options[:options] && options[:options]["dataVolume#{volume_index}"]) || Morpheus::Cli::OptionTypes.confirm("Add another data volume?")
        end

      end

    end

    return volumes
  end

end
