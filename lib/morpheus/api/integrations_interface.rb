require 'morpheus/api/rest_interface'

class Morpheus::IntegrationsInterface < Morpheus::RestInterface

  def base_path
    "/api/integrations"
  end

  def refresh(id, params={}, payload={}, headers={})
    validate_id!(id)
    execute(method: :post, url: "#{base_path}/#{id}/refresh", params: params, payload: payload, headers: headers)
  end

end
