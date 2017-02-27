require 'morpheus/api/api_client'
# There is no authentication required for this API.
class Morpheus::SetupInterface < Morpheus::APIClient
  # def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
  #   @access_token = access_token
  #   @refresh_token = refresh_token
  #   @base_url = base_url
  #   @expires_at = expires_at
  # end

  def initialize(base_url)
    @base_url = base_url
  end

  def get(options={})
    url = "#{@base_url}/api/setup"
    # headers = {:params => {}, authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers = {:params => {}, 'Content-Type' => 'application/json' }
    headers[:params].merge!(options)
    execute(method: :get, url: url, headers: headers)
  end

  def init(options={})
    url = "#{@base_url}/api/setup/init"
    # headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers = { 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, timeout: 30, headers: headers, payload: payload.to_json)
  end

end
