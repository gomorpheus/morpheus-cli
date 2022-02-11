require 'morpheus/api/api_client'

class Morpheus::PowerSchedulesInterface < Morpheus::APIClient

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/power-schedules/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{@base_url}/api/power-schedules"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def create(options)
    url = "#{@base_url}/api/power-schedules"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, options)
    url = "#{@base_url}/api/power-schedules/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id)
    url = "#{@base_url}/api/power-schedules/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, timeout: 10, headers: headers}
    execute(opts)
  end

  def add_instances(id, payload)
    url = "#{@base_url}/api/power-schedules/#{id}/add-instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_instances(id, payload)
    url = "#{@base_url}/api/power-schedules/#{id}/remove-instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def add_servers(id, payload)
    url = "#{@base_url}/api/power-schedules/#{id}/add-servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_servers(id, payload)
    url = "#{@base_url}/api/power-schedules/#{id}/remove-servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, timeout: 10, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
