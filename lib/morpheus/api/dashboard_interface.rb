require 'morpheus/api/api_client'

class Morpheus::DashboardInterface < Morpheus::APIClient

  def get(params={})
    headers = {params: params, authorization: "Bearer #{@access_token}"}
    execute(method: :get, url: "/api/dashboard", headers: headers)
  end

  # [DEPRECATED] Use ActivityInterface.list() instead.
  def recent_activity(params={})
    headers = {params: params, authorization: "Bearer #{@access_token}"}
    execute(method: :get, url: "/api/dashboard/recent-activity", headers: headers)
  end

end
