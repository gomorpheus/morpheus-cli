require 'morpheus/api/api_client'

class Morpheus::NetworkSecurityServersInterface < Morpheus::APIClient

  def base_path
    "/api/network-security-servers"
  end

  def list(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id, params={})
    url = "#{base_path}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{base_path}/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    execute(method: :get, url: url, headers: headers)
  end
end
