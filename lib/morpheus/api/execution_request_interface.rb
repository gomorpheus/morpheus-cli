require 'morpheus/api/api_client'

class Morpheus::ExecutionRequestInterface < Morpheus::APIClient
    def initialize(access_token, refresh_token, expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/execution-request/#{id}"
    headers = { :params => params, authorization: "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(params, payload)
    url = "#{@base_url}/api/execution-request/execute"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def execute_against_lease(id, params, payload)
    url = "#{@base_url}/api/execution-request/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
