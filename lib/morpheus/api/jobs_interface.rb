require 'morpheus/api/api_client'

class Morpheus::JobsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil, api='jobs')
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

  def get(id, params={})
    url = "#{@api_url}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
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

  def update(id, payload, params={})
    url = "#{@api_url}/#{id}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    url = "#{@api_url}/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def execute_job(id, params={})
    url = "#{@api_url}/#{id}/execute"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers)
  end

  def list_executions(params={})
    url = "#{@api_url}/executions"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_execution(id, params={})
    url = "#{@api_url}/executions/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def options(jobTypeId, params={})
    url = "#{@api_url}/options/#{jobTypeId}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list_targets(jobTypeId, params={})
    url = "#{@api_url}/targets/#{jobTypeId}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end
end
