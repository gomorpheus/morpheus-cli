require 'morpheus/api/api_client'

class Morpheus::NetworkServicesInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/networks/services"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(params={})
    url = "#{@base_url}/api/networks/services"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{url}/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    execute(method: :get, url: url, headers: headers)
  end

  def get_server(server_id)
    execute(method: :get, url: "#{@base_url}/api/networks/servers/#{server_id}", params: {}, headers: {})
  end

  def list_servers()
    execute(method: :get, url: "#{@base_url}/api/networks/servers", params: {}, headers: {})
  end

  def refresh(server_id)
    url = "#{@base_url}/api/networks/servers/#{server_id}/refresh"

    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers}
    execute(opts)
  end

  # def create(payload)
  #   url = "#{@base_url}/api/networks/services"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  # def update(id, payload)
  #   url = "#{@base_url}/api/networks/services/#{id}"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  # def destroy(id, params={})
  #   url = "#{@base_url}/api/networks/services/#{id}"
  #   headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :delete, url: url, headers: headers}
  #   execute(opts)
  # end

end
