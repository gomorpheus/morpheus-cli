require 'morpheus/api/api_client'

class Morpheus::InstancesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(params={}, options={})
    url = "#{@base_url}/api/instances"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{@base_url}/api/instances/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def list(params={}, options={})
    get(params, options)
  end

  def get_envs(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/envs"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def create_env(id, payload={}, options={})
    url = "#{@base_url}/api/instances/#{id}/envs"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def del_env(id, name, options={})
    url = "#{@base_url}/api/instances/#{id}/envs/#{name}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts, options)
  end

  def create(payload, options={})
    url = "#{@base_url}/api/instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def update(id, payload, options={})
    url = "#{@base_url}/api/instances/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def destroy(id, params = {}, options={})
    url = "#{@base_url}/api/instances/#{id}"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts, options)
  end

  def stop(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/stop"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def start(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/start"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def restart(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/restart"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def suspend(id, params={}, options={})
    url = "#{@base_url}/api/instances/suspend"
    if id.is_a?(Array)
      params['ids'] = id
    else
      url = "#{@base_url}/api/instances/#{id}/suspend"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def eject(id, params={}, options={})
    url = "#{@base_url}/api/instances/eject"
    if id.is_a?(Array)
      params['ids'] = id
    else
      url = "#{@base_url}/api/instances/#{id}/eject"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def available_actions(id, options={})
    url, params = "", {}
    if id.is_a?(Array)
      url = "#{@base_url}/api/instances/actions"
      params = {ids: id}
    else
      url = "#{@base_url}/api/instances/#{id}/actions"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def action(id, action_code, payload={}, options={})
    url, params = "", {}
    if id.is_a?(Array)
      url = "#{@base_url}/api/instances/action"
      params = {ids: id, code: action_code}
    else
      url = "#{@base_url}/api/instances/#{id}/action"
      params = {code: action_code}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def volumes(id, options={})
    url = "#{@base_url}/api/instances/#{id}/volumes"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options={})
  end

  def resize(id,payload, options={})
    url = "#{@base_url}/api/instances/#{id}/resize"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers,payload: payload.to_json}
    execute(opts, options)
  end

  def workflow(id,task_set_id,payload, options={})
    url = "#{@base_url}/api/instances/#{id}/workflow"
    headers = { :params => {:taskSetId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers,payload: payload.to_json}
    execute(opts, options)
  end

  def backup(id,server=true, options={})
    url = "#{@base_url}/api/instances/#{id}/backup"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def backups(id, params, options={})
    url = "#{@base_url}/api/instances/#{id}/backups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def clone(id, payload, options={})
    url = "#{@base_url}/api/instances/#{id}/clone"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options={})
  end

  def firewall_disable(id, options={})
    url = "#{@base_url}/api/instances/#{id}/security-groups/disable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def firewall_enable(id, options={})
    url = "#{@base_url}/api/instances/#{id}/security-groups/enable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def security_groups(id, options={})
    url = "#{@base_url}/api/instances/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def apply_security_groups(id, payload, options={})
    url = "#{@base_url}/api/instances/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end
    def import_snapshot(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/import-snapshot"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def service_plans(params={}, options={})
    url = "#{@base_url}/api/instances/service-plans"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def containers(instance_id, params={}, options={})
    url = "#{@base_url}/api/instances/#{instance_id}/containers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def threshold(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/threshold"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def update_threshold(id, payload, options={})
    url = "#{@base_url}/api/instances/#{id}/threshold"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def update_load_balancer(id, payload, options={})
    url = "#{@base_url}/api/instances/#{id}/load-balancer"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def remove_load_balancer(id, payload={}, options={})
    url = "#{@base_url}/api/instances/#{id}/load-balancer"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def update_notes(id, payload, options={})
    url = "#{@base_url}/api/instances/#{id}/notes"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def history(id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/history"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def history_details(id, process_id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/history/#{process_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def history_event_details(id, process_event_id, params={}, options={})
    url = "#{@base_url}/api/instances/#{id}/history/events/#{process_event_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

end
