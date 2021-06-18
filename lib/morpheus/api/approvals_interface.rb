require 'morpheus/api/api_client'

class Morpheus::ApprovalsInterface < Morpheus::APIClient
  
  def base_path
    "/api/approvals"
  end

  def list(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id, params={})
    url = "#{base_path}/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_item(id, params={})
    url = "#{@base_url}/api/approval-items/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update_item(id, action)
    url = "#{@base_url}/api/approval-items/#{id}/#{action}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers)
  end
end
