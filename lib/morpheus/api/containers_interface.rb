require 'morpheus/api/api_client'

# Containers API interface.
# All of the PUT methods support passing an array of IDs.
class Morpheus::ContainersInterface < Morpheus::APIClient

  def base_path
    "/api/containers"
  end
  # not used atm.. index api needs some work, we should implement it 
  # so it just paginates all containers. 
  # right now you can to pass params as {:ids => [1,2,3]}
  def list(params={})
    url = "#{base_path}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(container_id)
    url = "#{base_path}/#{container_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def stop(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/stop"
      params = {ids: container_id}
    else
      url = "#{base_path}/#{container_id}/stop"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def start(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/start"
      params = {ids: container_id}
    else
      url = "#{base_path}/#{container_id}/start"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def restart(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/restart"
      params = {ids: container_id}
    else
      url = "#{base_path}/#{container_id}/restart"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def suspend(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/suspend"
      params = {ids: container_id}
    else
      url = "#{base_path}/#{container_id}/suspend"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def eject(container_id, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/eject"
      params = {ids: container_id}
    else
      url = "#{base_path}/#{container_id}/eject"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def available_actions(container_id)
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/actions"
      params = {ids: container_id}
    else
      url = "#{base_path}/#{container_id}/actions"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def action(container_id, action_code, payload={})
    url, params = "", {}
    if container_id.is_a?(Array)
      url = "#{base_path}/action"
      params = {ids: container_id, code: action_code}
    else
      url = "#{base_path}/#{container_id}/action"
      params = {code: action_code}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def import(container_id, payload={}, headers={})
    validate_id!(container_id)
    execute(method: :put, url: "#{base_path}/#{container_id}/import", payload: payload, headers: headers)
  end

  def clone_image(container_id, payload={}, headers={})
    validate_id!(container_id)
    execute(method: :put, url: "#{base_path}/#{container_id}/clone-image", payload: payload, headers: headers)
  end

end
