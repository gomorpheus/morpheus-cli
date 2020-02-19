require 'morpheus/api/api_client'

class Morpheus::LibrarySpecTemplateTypesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/library/spec-template-types/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{@base_url}/api/library/spec-template-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  # def create(options)
  #   url = "#{@base_url}/api/library/spec-template-types"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   payload = options
  #   opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  # def update(id, options)
  #   url = "#{@base_url}/api/library/spec-template-types/#{id}"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   payload = options
  #   opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  # def destroy(id, payload={})
  #   url = "#{@base_url}/api/library/spec-template-types/#{id}"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

end
