require 'morpheus/api/api_client'

class Morpheus::UserSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/user-settings"
  end

  def get(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def update(payload, params={}, headers={})
    execute(method: :put, url: "#{base_path}", params: params, payload: payload, headers: headers)
  end

  # download file as attachment
  def download_avatar(params, outfile)
    url = "#{base_path}/avatar"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  # multipart file upload
  def update_avatar(avatar_file, params={})
    url = "#{base_path}/avatar"
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
    url = "#{base_path}/avatar"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    # POST empty payload will do
    payload = {}
    opts = {method: :delete, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  # multipart file upload
  def update_desktop_background(desktop_background_file, params={})
    url = "#{base_path}/desktop-background"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    payload = {}
    #payload['user'] ||= {}
    #payload['user']['desktopBackground'] = desktop_background_file
    payload['user.desktopBackground'] = desktop_background_file
    payload[:multipart] = true
    opts = {method: :post, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  def remove_desktop_background(params={})
    url = "#{base_path}/desktop-background"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    # POST empty payload will do
    payload = {}
    opts = {method: :delete, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  def regenerate_access_token(params, payload={})
    url = "#{base_path}/regenerate-access-token"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def clear_access_token(params, payload={})
    url = "#{base_path}/clear-access-token"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def available_clients(params={})
    url = "#{base_path}/api-clients"
    headers = { :params => params, authorization: "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
