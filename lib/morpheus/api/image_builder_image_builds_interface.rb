require 'morpheus/api/api_client'
# this may change to just /api/image-builds
class Morpheus::ImageBuilderImageBuildsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/image-builds/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{@base_url}/api/image-builds"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/image-builds"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  # def validate_save(payload)
  #   url = "#{@base_url}/api/image-builds/validate-save"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  def update(id, payload)
    url = "#{@base_url}/api/image-builds/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/image-builds/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, timeout: 30, headers: headers}
    execute(opts)
  end

  def run(id, params={})
    url = "#{@base_url}/api/image-builds/#{id}/run"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, timeout: 30, headers: headers}
    execute(opts)
  end

  def list_executions(id, params={})
    url = "#{@base_url}/api/image-builds/#{id}/list-executions"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
