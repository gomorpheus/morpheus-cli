require 'morpheus/api/read_interface'

class Morpheus::LoadBalancerTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/load-balancer-types"
  end

end
