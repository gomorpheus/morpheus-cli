require 'morpheus/api/rest_interface'

class Morpheus::IntegrationsInterface < Morpheus::RestInterface

  def base_path
    "/api/integrations"
  end

end
