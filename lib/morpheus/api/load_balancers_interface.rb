require 'morpheus/api/rest_interface'

class Morpheus::LoadBalancersInterface < Morpheus::RestInterface

  def base_path
    "/api/load-balancers"
  end

  def refresh(id, payload, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}/refresh", params: params, payload: payload, headers: headers)
  end

end
