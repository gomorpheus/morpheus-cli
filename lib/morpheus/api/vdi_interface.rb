require 'morpheus/api/api_client'

# Interface for VDI Persona that provides viewing and allocating virtual desktops (VDI pools)
class Morpheus::VdiInterface < Morpheus::APIClient

  def base_path
    "/api/vdi"
  end

  # def dashboard(params={})
  #   execute(method: :get, url: "#{base_path}/dashboard", params: params)
  # end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

  def get(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params)
  end

  def allocate(id, payload, params={})
    validate_id!(id)
    execute(method: :post, url: "#{base_path}/#{id}/allocate", params: params, payload: payload.to_json)
  end

end
