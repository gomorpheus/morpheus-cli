require 'morpheus/api/api_client'

class Morpheus::ActivityInterface < Morpheus::APIClient

  def list(params={})
    headers = {params: params, authorization: "Bearer #{@access_token}"}
    execute(method: :get, url: "/api/activity", headers: headers)
  end

end
