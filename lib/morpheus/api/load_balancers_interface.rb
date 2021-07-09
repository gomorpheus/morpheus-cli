require 'morpheus/api/rest_interface'

class Morpheus::LoadBalancersInterface < Morpheus::RestInterface

  def base_path
    "/api/load-balancers"
  end

end
