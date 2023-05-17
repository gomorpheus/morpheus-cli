require 'morpheus/api/secondary_rest_interface'

class Morpheus::LoadBalancerPoolsSecondaryInterface < Morpheus::SecondaryRestInterface

  def base_path(load_balancer_id)
    "/api/load-balancers/#{load_balancer_id}/pools"
  end

end
