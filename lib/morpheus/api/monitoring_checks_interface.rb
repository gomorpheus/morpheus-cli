require 'morpheus/api/api_client'

class Morpheus::MonitoringChecksInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id)
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/monitoring/checks/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(options={})
    url = "#{@base_url}/api/monitoring/checks"
    headers = { params: options, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/monitoring/checks"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, options)
    url = "#{@base_url}/api/monitoring/checks/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id)
    url = "#{@base_url}/api/monitoring/checks/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def quarantine(id, options={})
    url = "#{@base_url}/api/monitoring/checks/#{id}/quarantine"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def history(id, params={})
    url = "#{@base_url}/api/monitoring/checks/#{id}/history"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def statistics(id)
    url = "#{@base_url}/api/monitoring/checks/#{id}/statistics"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list_check_types(options={})
    url = "#{@base_url}/api/monitoring/check-types"
    headers = { :params => options, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get_check_type(check_type_id)
    url = "#{@base_url}/api/monitoring/check-types/#{check_type_id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  # def events(id, params={})
  #   # JD: maybe switch to this instead /api/monitoring/checks/#{id}/events instead?
  #   # url = "#{@base_url}/api/monitoring/checks/#{id}/events"
  #   url = "#{@base_url}/api/monitoring/checks/#{id}/events"
  #   headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :get, url: url, headers: headers}
  #   execute(opts)
  # end

end
