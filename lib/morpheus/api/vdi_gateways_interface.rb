require 'morpheus/api/rest_interface'

class Morpheus::VdiGatewaysInterface < Morpheus::RestInterface

  def base_path
    "/api/vdi-gateways"
  end

end
