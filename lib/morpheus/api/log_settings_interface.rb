require 'morpheus/api/api_client'

class Morpheus::LogSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/log-settings"
  end

  def get(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = base_path
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_integration(name, payload, params={})
    url = "#{base_path}/integrations/#{name}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_integration(name, params={})
    url = "#{base_path}/integrations/#{name}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def add_syslog_rule(payload, params={})
    url = "#{base_path}/syslog-rules"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_syslog_rule(name, params={})
    url = "#{base_path}/syslog-rules/#{name}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
end
