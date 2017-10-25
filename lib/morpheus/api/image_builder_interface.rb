require 'morpheus/api/api_client'
require 'morpheus/api/image_builder_image_builds_interface'
require 'morpheus/api/image_builder_preseed_scripts_interface'
require 'morpheus/api/image_builder_boot_scripts_interface'

class Morpheus::ImageBuilderInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def image_builds
    Morpheus::ImageBuilderImageBuildsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def preseed_scripts
    Morpheus::ImageBuilderPreseedScriptsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def boot_scripts
    Morpheus::ImageBuilderBootScriptsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end
  
end
