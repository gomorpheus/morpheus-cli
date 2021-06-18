require 'morpheus/api/api_client'

class Morpheus::AccountGroupsInterface < Morpheus::APIClient

  def get(account_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/accounts/#{account_id}/groups/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(account_id, params={})
    url = "#{@base_url}/api/accounts/#{account_id}/groups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(account_id, payload)
    url = "#{@base_url}/api/accounts/#{account_id}/groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(account_id, id, payload)
    url = "#{@base_url}/api/accounts/#{account_id}/groups/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(account_id, id, params={})
    url = "#{@base_url}/api/accounts/#{account_id}/groups/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def update_zones(account_id, id, payload)
    url = "#{@base_url}/api/accounts/#{account_id}/groups/#{id}/update-zones"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
