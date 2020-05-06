require 'morpheus/api/api_client'

class Morpheus::ActivityInterface < Morpheus::APIClient

  def list(params={})
    execute(method: :get, url: "/api/activity", headers: {params: params})
  end

end
