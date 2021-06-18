require 'morpheus/api/api_client'

class Morpheus::ProvisioningLicenseTypesInterface < Morpheus::APIClient

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
