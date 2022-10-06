require 'morpheus/api/api_client'

class Morpheus::ClientsInterface < Morpheus::APIClient
  def base_path
    "/api/clients"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end
end