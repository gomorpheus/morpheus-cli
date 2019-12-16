require 'morpheus/api/api_client'

class Morpheus::LogSettingsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil, api='log-settings')
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @api_url = "#{base_url}/api/#{api}"
    @expires_at = expires_at
  end

  def get(params={})
    url = @api_url
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = @api_url
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_integration(name, payload, params={})
    url = "#{@api_url}/integrations/#{name}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_integration(name, params={})
    url = "#{@api_url}/integrations/#{name}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def add_syslog_rule(payload, params={})
    url = "#{@api_url}/syslog-rules"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_syslog_rule(name, params={})
    url = "#{@api_url}/syslog-rules/#{name}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
end
