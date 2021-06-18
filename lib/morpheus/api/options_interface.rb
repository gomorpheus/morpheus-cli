require 'morpheus/api/api_client'

class Morpheus::OptionsInterface < Morpheus::APIClient

  def options_for_source(source,params = {})
    url = "#{@base_url}/api/options/#{source}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end
end
