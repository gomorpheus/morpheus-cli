require 'morpheus/api/secondary_rest_interface'

class Morpheus::LoadBalancerVirtualServersInterface < Morpheus::SecondaryRestInterface

  def base_path(load_balancer_id)
    "/api/load-balancers/#{load_balancer_id}/virtual-servers"
  end

  def list(parent_id=nil, params={}, headers={})
    if parent_id
      validate_id!(parent_id)
      execute(method: :get, url: "#{base_path(parent_id)}", params: params, headers: headers)
    else
      execute(method: :get, url: "/api/load-balancer-virtual-servers", params: params, headers: headers)
    end
  end

end
