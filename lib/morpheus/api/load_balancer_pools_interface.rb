require 'morpheus/api/rest_interface'

class Morpheus::LoadBalancerPoolsInterface < Morpheus::RestInterface

  def base_path
    "/api/load-balancer-pools"
  end

end
