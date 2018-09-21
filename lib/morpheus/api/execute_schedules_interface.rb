require 'morpheus/api/api_client'

class Morpheus::ExecuteSchedulesInterface < Morpheus::APIClient
    def initialize(access_token, refresh_token, expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id)
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/execute-schedules/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def list(options={})
    url = "#{@base_url}/api/execute-schedules"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def create(options)
    url = "#{@base_url}/api/execute-schedules"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, options)
    url = "#{@base_url}/api/execute-schedules/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id)
    url = "#{@base_url}/api/execute-schedules/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def add_instances(id, payload)
    url = "#{@base_url}/api/execute-schedules/#{id}/add-instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_instances(id, payload)
    url = "#{@base_url}/api/execute-schedules/#{id}/remove-instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def add_servers(id, payload)
    url = "#{@base_url}/api/execute-schedules/#{id}/add-servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_servers(id, payload)
    url = "#{@base_url}/api/execute-schedules/#{id}/remove-servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
