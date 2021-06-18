require 'morpheus/api/api_client'

class Morpheus::ProvisioningLicensesInterface < Morpheus::APIClient

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

  def create(payload)
    url = build_url()
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = build_url(id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = build_url(id)
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def reservations(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = build_url(id) + "/reservations"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  private

  def build_url(id=nil)
    url = "#{@base_url}/api/provisioning-licenses"
    if id
      url += "/#{id}"
    end
    url
  end


end
