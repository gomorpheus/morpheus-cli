require 'morpheus/api/api_client'

class Morpheus::DashboardInterface < Morpheus::APIClient

  def get(params={})
    execute(method: :get, url: "/api/dashboard", headers: {params: params})
  end

  # [DEPRECATED] Use ActivityInterface.list() instead.
  def recent_activity(params={})
    execute(method: :get, url: "/api/dashboard/recent-activity", headers: {params: params})
  end

end
