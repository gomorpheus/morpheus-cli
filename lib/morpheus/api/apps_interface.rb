require 'morpheus/api/api_client'

class Morpheus::AppsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end


  def get(params={}, options={})
    url = "#{@base_url}/api/apps"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{@base_url}/api/apps/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def validate(payload, options={})
    # url = "#{@base_url}/api/apps/validate-instance"
    url = "#{@base_url}/api/apps/validate"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def validate_instance(payload, options={})
    # url = "#{@base_url}/api/apps/validate-instance"
    url = "#{@base_url}/api/apps/validate-instance"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def create(payload, options={})
    url = "#{@base_url}/api/apps"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def update(app_id, payload, options={})
    url = "#{@base_url}/api/apps/#{app_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def add_instance(app_id, payload, options={})
    url = "#{@base_url}/api/apps/#{app_id}/add-instance"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def remove_instance(app_id, payload, options={})
    url = "#{@base_url}/api/apps/#{app_id}/remove-instance"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end

  def destroy(id, params={}, options={})
    url = "#{@base_url}/api/apps/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers[:params] = params
    opts = {method: :delete, url: url, headers: headers}
    execute(opts, options)
  end

  def stop(id, options={})
    url = "#{@base_url}/api/apps/#{id}/stop"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def start(id, options={})
    url = "#{@base_url}/api/apps/#{id}/start"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def restart(id, options={})
    url = "#{@base_url}/api/apps/#{id}/restart"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def firewall_disable(id, options={})
    url = "#{@base_url}/api/apps/#{id}/security-groups/disable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def firewall_enable(id, options={})
    url = "#{@base_url}/api/apps/#{id}/security-groups/enable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts, options)
  end

  def security_groups(id, options={})
    url = "#{@base_url}/api/apps/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, options)
  end

  def apply_security_groups(id, payload, options={})
    url = "#{@base_url}/api/apps/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts, options)
  end
end
