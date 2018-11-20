require 'morpheus/api/api_client'

class Morpheus::UserSettingsInterface < Morpheus::APIClient
    def initialize(access_token, refresh_token, expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(params={})
    url = "#{@base_url}/api/user-settings"
    headers = { :params => params, authorization: "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update(params, payload)
    url = "#{@base_url}/api/user-settings"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  # NOT json, download file as attachment
  def download_avatar(params, outfile)
    url = "#{@base_url}/api/user-settings/avatar"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  # NOT json, multipart file upload
  def update_avatar(avatar_file, params={})
    url = "#{@base_url}/api/user-settings/avatar"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    payload = {}
    #payload['user'] ||= {}
    #payload['user']['avatar'] = avatar_file
    payload['user.avatar'] = avatar_file
    payload[:multipart] = true
    opts = {method: :post, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  def remove_avatar(params={})
    url = "#{@base_url}/api/user-settings/avatar"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    # POST empty payload will do
    payload = {}
    opts = {method: :delete, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  def regenerate_access_token(params, payload={})
    url = "#{@base_url}/api/user-settings/regenerate-access-token"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def clear_access_token(params, payload={})
    url = "#{@base_url}/api/user-settings/clear-access-token"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def available_clients(params={})
    url = "#{@base_url}/api/user-settings/api-clients"
    headers = { :params => params, authorization: "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
