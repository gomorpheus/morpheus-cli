require 'morpheus/api/api_client'

# Containers API interface.
# All of the PUT methods support passing an array of IDs.
class Morpheus::ContainersInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  # not used atm.. index api needs some work, we should implement it 
  # so it just paginates all containers. 
  # right now you can to pass params as {:ids => [1,2,3]}
  def list(params={})
    url = "#{@base_url}/api/containers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(container_id)
    url = "#{@base_url}/api/containers/#{container_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def stop(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/stop"
      params = {ids: container_id}
    else
      url = "#{@base_url}/api/containers/#{container_id}/stop"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def start(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/start"
      params = {ids: container_id}
    else
      url = "#{@base_url}/api/containers/#{container_id}/start"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def restart(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/restart"
      params = {ids: container_id}
    else
      url = "#{@base_url}/api/containers/#{container_id}/restart"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def suspend(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/suspend"
      params = {ids: container_id}
    else
      url = "#{@base_url}/api/containers/#{container_id}/suspend"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def eject(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/eject"
      params = {ids: container_id}
    else
      url = "#{@base_url}/api/containers/#{container_id}/eject"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def available_actions(container_id)
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/actions"
      params = {ids: container_id}
    else
      url = "#{@base_url}/api/containers/#{container_id}/actions"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def action(container_id, action_code, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{@base_url}/api/containers/action"
      params = {ids: container_id, code: action_code}
    else
      url = "#{@base_url}/api/containers/#{container_id}/action"
      params = {code: action_code}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
