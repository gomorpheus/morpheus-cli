require 'morpheus/api/api_client'

class Morpheus::ServersInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(options=nil)
    url = "#{@base_url}/api/servers"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/servers/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(options={})
    get(options)
  end

  def create(options)
    url = "#{@base_url}/api/servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(serverId, options)
    url = "#{@base_url}/api/servers/#{serverId}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def stop(serverId,payload = {}, params={})
    url = "#{@base_url}/api/servers/stop"
    if serverId.is_a?(Array)
      params['ids'] = serverId
    else
      url = "#{@base_url}/api/servers/#{serverId}/stop"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def start(serverId,payload = {}, params = {})
    url = "#{@base_url}/api/servers/start"
    if serverId.is_a?(Array)
      params['ids'] = serverId
    else
      url = "#{@base_url}/api/servers/#{serverId}/start"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def install_agent(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/install-agent"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def upgrade(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/upgrade"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def reprovision(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/reprovision"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def reinitialize(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/reinitialize"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def assign_account(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/assign-account"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def workflow(id,task_set_id,payload)
    url = "#{@base_url}/api/servers/#{id}/workflow"
    headers = { :params => {:taskSetId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/servers/#{id}"
    headers = { :params => params,:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def service_plans(params)
    url = "#{@base_url}/api/servers/service-plans"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def volumes(id)
    url = "#{@base_url}/api/servers/#{id}/volumes"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def resize(id,payload)
    url = "#{@base_url}/api/servers/#{id}/resize"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
