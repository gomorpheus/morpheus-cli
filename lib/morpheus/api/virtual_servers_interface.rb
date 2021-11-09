require 'morpheus/api/rest_interface'

class Morpheus::VirtualServersInterface < Morpheus::RestInterface

  def base_path
    "/api/load-balancer-virtual-servers"
  end

end
