require 'morpheus/api/secondary_rest_interface'

class Morpheus::LoadBalancerVirtualServersInterface < Morpheus::SecondaryRestInterface

  def base_path(load_balancer_id)
    "/api/load-balancers/#{load_balancer_id}/virtual-servers"
  end

end
