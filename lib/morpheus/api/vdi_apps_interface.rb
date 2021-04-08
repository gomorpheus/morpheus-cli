require 'morpheus/api/rest_interface'

class Morpheus::VdiAppsInterface < Morpheus::RestInterface

  def base_path
    "/api/vdi-apps"
  end

end
