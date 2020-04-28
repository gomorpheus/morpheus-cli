require 'morpheus/api/api_client'

class Morpheus::WhoamiInterface < Morpheus::APIClient

  def default_timeout
    5
  end

  def get(params={})
    execute(method: :get, url: "/api/whoami", params: params)
  end

end
