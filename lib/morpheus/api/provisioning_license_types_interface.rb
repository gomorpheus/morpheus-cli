require 'morpheus/api/api_client'

class Morpheus::ProvisioningLicenseTypesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = build_url(id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = build_url()
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  private

  def build_url(id=nil)
    url = "#{@base_url}/api/provisioning-license-types"
    if id
      url += "/#{id}"
    end
    url
  end


end
