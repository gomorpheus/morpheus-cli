require 'morpheus/api/api_client'

class Morpheus::ClientsInterface < Morpheus::APIClient

  def list(params={}, headers={})
    url = "#{@base_url}/api/clients"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
     raise "#{self.class}.get() passed a blank name!" if id.to_s == ''
    url = "#{@base_url}/api/clients/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

   def create(payload)
    url = "#{@base_url}/api/clients"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/clients/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/clients/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

end