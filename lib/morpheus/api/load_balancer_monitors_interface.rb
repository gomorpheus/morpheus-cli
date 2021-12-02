require 'morpheus/api/secondary_rest_interface'

class Morpheus::LoadBalancerMonitorsInterface < Morpheus::SecondaryRestInterface

  def base_path(load_balancer_id)
    "/api/load-balancers/#{load_balancer_id}/monitors"
  end

end
