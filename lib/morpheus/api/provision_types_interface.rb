require 'morpheus/api/api_client'

class Morpheus::ProvisionTypesInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/provision-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(options=nil)
    url = "#{@base_url}/api/provision-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/provision-types/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end
end
