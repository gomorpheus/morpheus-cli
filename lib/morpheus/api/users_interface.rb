require 'morpheus/api/api_client'

class Morpheus::UsersInterface < Morpheus::APIClient

  def get(account_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = build_url(account_id, id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def list(account_id, params={})
    url = build_url(account_id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def feature_permissions(account_id, id)
    url = build_url(account_id, id) + "/feature-permissions"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def permissions(account_id, id)
    url = build_url(account_id, id) + "/permissions"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def available_roles(account_id, id=nil, options={})
    url = build_url(account_id, id) + "/available-roles"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def create(account_id, options)
    url = build_url(account_id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(account_id, id, options)
    url = build_url(account_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(account_id, id)
    url = build_url(account_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  private

  def build_url(account_id=nil, user_id=nil)
    url = "#{@base_url}/api"
    if account_id
      url += "/accounts/#{account_id}/users"
    else
      url += "/users"
    end
    if user_id
      url += "/#{user_id}"
    end
    url
  end

end
