require 'morpheus/api/api_client'

class Morpheus::DatastoresInterface < Morpheus::APIClient

  def base_path
    "/api/data-stores"
  end

  def list(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def types(params={})
    url = "/api/data-store-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end
end
