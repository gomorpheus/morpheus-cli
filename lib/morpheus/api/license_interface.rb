require 'morpheus/api/api_client'

class Morpheus::LicenseInterface < Morpheus::APIClient

  def get()
    url = "#{@base_url}/api/license"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def install(key)
    url = "#{@base_url}/api/license"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = {license: key}
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def test(key)
    # use /test instead, since 4.1.1
    url = "#{@base_url}/api/license/decode"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = {license: key}
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def uninstall(params={})
    url = "#{@base_url}/api/license"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

end
