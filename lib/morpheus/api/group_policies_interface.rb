require 'morpheus/api/api_client'

class Morpheus::GroupPoliciesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(group_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/groups/#{group_id}/policies/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(group_id, params={})
    url = "#{@base_url}/api/groups/#{group_id}/policies"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(group_id, payload)
    url = "#{@base_url}/api/groups/#{group_id}/policies"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(group_id, id, payload)
    url = "#{@base_url}/api/groups/#{group_id}/policies/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(group_id, id, params={})
    url = "#{@base_url}/api/groups/#{group_id}/policies/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

end
