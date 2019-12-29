require 'morpheus/api/api_client'

class Morpheus::HealthInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(params={})
    url = "#{@base_url}/api/health"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def live(params={})
    url = "#{@base_url}/api/health/live"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def alarms(params={})
    list_alarms(params)
  end

  def list_alarms(params={})
    url = "#{@base_url}/api/health/alarms"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get_alarm(id, params={})
    raise "#{self.class}.get() passed a blank name!" if id.to_s == ''
    url = "#{@base_url}/api/health/alarms/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def acknowledge_alarm(id, params={}, payload={})
    url = "#{@base_url}/api/health/alarms/#{id}/acknowledge"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def acknowledge_alarms(params, payload={})
    url = "#{@base_url}/api/health/alarms/acknowledge"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def logs(params={})
    url = "#{@base_url}/api/health/logs"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def notifications(params={})
    url = "#{@base_url}/api/health/notifications"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
