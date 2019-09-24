require 'morpheus/api/api_client'

class Morpheus::ClustersInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil, api='clusters')
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @api_url = "#{base_url}/api/#{api}"
    @expires_at = expires_at
  end

  def list(params={})
    url = @api_url
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(params={})
    url = @api_url
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{@api_url}/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = @api_url
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{@api_url}/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    url = "#{@api_url}/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  alias :delete :destroy

  def cluster_types(params={})
    url = "#{@base_url}/api/cluster-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list_jobs(id, params={})
    url = "#{@api_url}/#{id}/jobs"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list_masters(id, params={})
    url = "#{@api_url}/#{id}/masters"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list_workers(id, params={})
    url = "#{@api_url}/#{id}/workers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def add_server(id, payload)
    url = "#{@api_url}/#{id}/servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def list_volumes(id, params={})
    url = "#{@api_url}/#{id}/volumes"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  # this supports multiple ids
  def destroy_volume(id, volume_id=nil, params={}, payload={})
    url = nil
    if volume_id.is_a?(Array)
      url = "#{@api_url}/#{id}/volumes"
      params['volumeId'] = volume_id
    elsif volume_id.is_a?(Numeric) || volume_id.is_a?(String)
      url = "#{@api_url}/#{id}/volumes/#{volume_id}"
    else
      raise "passed a bad volume_id: #{volume_id || '(none)'}" # lazy
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers, payload: payload.to_json)
  end

  alias :delete_volume :destroy_volume

  def list_namespaces(id, params={})
    url = "#{@api_url}/#{id}/namespaces"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_namespace(id, namespace_id, params={})
    url = "#{@api_url}/#{id}/namespaces/#{namespace_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create_namespace(id, payload)
    url = "#{@api_url}/#{id}/namespaces"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update_namespace(id, namespace_id, payload)
    url = "#{@api_url}/#{id}/namespaces/#{namespace_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_namespace(id, namespace_id, params={})
    url = "#{@api_url}/#{id}/namespaces/#{namespace_id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
  
  alias :delete_namespace :destroy_namespace

  def list_containers(id, params={})
    url = "#{@api_url}/#{id}/containers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  # def list_pods(id, params={})
  #   url = "#{@api_url}/#{id}/pods"
  #   headers = { params: params, authorization: "Bearer #{@access_token}" }
  #   execute(method: :get, url: url, headers: headers)
  # end

  def wiki(id, params)
    url = "#{@base_url}/api/clusters/#{id}/wiki"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_wiki(id, payload)
    url = "#{@base_url}/api/clusters/#{id}/wiki"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
