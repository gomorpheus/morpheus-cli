require 'morpheus/api/api_client'

class Morpheus::LibraryOperatingSystemsInterface < Morpheus::APIClient

  def list_os_types(params={})
    url = "#{@base_url}/api/library/operating-systems/os-types"
    params['sort'] = 'name'
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/library/operating-systems/os-types/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get_image(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/library/operating-systems/os-types/images/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create_image(payload)
    url = "#{@base_url}/api/library/operating-systems/os-types/create-image"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy_image(id, payload={})
    url = "#{@base_url}/api/library/operating-systems/os-types/images/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end
end