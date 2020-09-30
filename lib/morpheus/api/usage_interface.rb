require 'morpheus/api/api_client'

class Morpheus::UsageInterface < Morpheus::APIClient

  def base_path
    "/api/usage" # not /usages ?
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

  def get(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params)
  end

end
