require 'morpheus/api/api_client'

class Morpheus::InstancesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(options=nil)
    url = "#{@base_url}/api/instances"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/instances/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(options={})
    get(options)
  end

  def get_envs(id, options=nil)
    url = "#{@base_url}/api/instances/#{id}/envs"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create_env(id, options)
    url = "#{@base_url}/api/instances/#{id}/envs"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def del_env(id, name)
    url = "#{@base_url}/api/instances/#{id}/envs/#{name}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def create(options)
    url = "#{@base_url}/api/instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, options)
    url = "#{@base_url}/api/instances/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params = {})
    url = "#{@base_url}/api/instances/#{id}"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def stop(id, params={})
    url = "#{@base_url}/api/instances/#{id}/stop"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def start(id, params={})
    url = "#{@base_url}/api/instances/#{id}/start"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def restart(id, params={})
    url = "#{@base_url}/api/instances/#{id}/restart"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def suspend(id, params={})
    url = "#{@base_url}/api/instances/#{id}/suspend"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def eject(id, params={})
    url = "#{@base_url}/api/instances/#{id}/eject"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def available_actions(id)
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
    execute(opts)
  end

  def action(id, action_code, payload={})
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
    execute(opts)
  end

  def volumes(id)
    url = "#{@base_url}/api/instances/#{id}/volumes"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def resize(id,payload)
    url = "#{@base_url}/api/instances/#{id}/resize"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers,payload: payload.to_json}
    execute(opts)
  end

  def workflow(id,task_set_id,payload)
    url = "#{@base_url}/api/instances/#{id}/workflow"
    headers = { :params => {:taskSetId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers,payload: payload.to_json}
    execute(opts)
  end

  def backup(id,server=true)
    url = "#{@base_url}/api/instances/#{id}/backup"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def backups(id, params)
    url = "#{@base_url}/api/instances/#{id}/backups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def clone(id, options)
    url = "#{@base_url}/api/instances/#{id}/clone"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def firewall_disable(id)
    url = "#{@base_url}/api/instances/#{id}/security-groups/disable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def firewall_enable(id)
    url = "#{@base_url}/api/instances/#{id}/security-groups/enable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def security_groups(id)
    url = "#{@base_url}/api/instances/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def apply_security_groups(id, options)
    url = "#{@base_url}/api/instances/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end
    def import_snapshot(id, params={})
    url = "#{@base_url}/api/instances/#{id}/import-snapshot"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def service_plans(params)
    url = "#{@base_url}/api/instances/service-plans"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def containers(instance_id, params={})
    url = "#{@base_url}/api/instances/#{instance_id}/containers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def threshold(id, params={})
    url = "#{@base_url}/api/instances/#{id}/threshold"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_threshold(id, payload)
    url = "#{@base_url}/api/instances/#{id}/threshold"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_load_balancer(id, payload)
    url = "#{@base_url}/api/instances/#{id}/load-balancer"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_load_balancer(id, payload={})
    url = "#{@base_url}/api/instances/#{id}/load-balancer"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_notes(id, payload)
    url = "#{@base_url}/api/instances/#{id}/notes"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
