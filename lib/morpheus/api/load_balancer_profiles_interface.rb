require 'morpheus/api/rest_interface'

class Morpheus::LoadBalancerProfilesInterface < Morpheus::RestInterface

  def base_path
    "/api/load-balancer-profiles"
  end

end

