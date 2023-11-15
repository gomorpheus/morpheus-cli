require 'morpheus/api/api_client'

class Morpheus::LibraryClusterPackagesInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/library/cluster-packages"
    params['sort'] = 'name'
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/library/cluster-packages/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/library/cluster-packages"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/library/cluster-packages/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, payload={})
    url = "#{@base_url}/api/library/cluster-packages/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_logo(id, logo_file, dark_logo_file=nil)
    url = "#{@base_url}/api/library/cluster-packages/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload["clusterPackage"] = {}
    if logo_file
      payload["clusterPackage"]["logo"] = logo_file
    end
    if dark_logo_file
      payload["clusterPackage"]["darkLogo"] = dark_logo_file
    end
    if logo_file.is_a?(File) || dark_logo_file.is_a?(File)
      payload[:multipart] = true
    else
      headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end
    execute(method: :put, url: url, headers: headers, payload: payload)
  end
end