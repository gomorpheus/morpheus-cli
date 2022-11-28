require 'morpheus/api/api_client'
# require 'morpheus/api/image_builder_image_builds_interface'
# require 'morpheus/api/image_builder_preseed_scripts_interface'
# require 'morpheus/api/image_builder_boot_scripts_interface'

class Morpheus::ImageBuilderInterface < Morpheus::APIClient

  def image_builds
    Morpheus::ImageBuilderImageBuildsInterface.new(common_interface_options).setopts(@options)
  end

  def preseed_scripts
    Morpheus::ImageBuilderPreseedScriptsInterface.new(common_interface_options).setopts(@options)
  end

  def boot_scripts
    Morpheus::ImageBuilderBootScriptsInterface.new(common_interface_options).setopts(@options)
  end
  
end
