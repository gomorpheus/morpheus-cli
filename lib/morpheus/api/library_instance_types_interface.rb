require 'morpheus/api/api_client'

class Morpheus::LibraryInstanceTypesInterface < Morpheus::APIClient

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    # new URL is available in api 4.2 +
    # url = "#{@base_url}/api/library/#{id}"
    url = "#{@base_url}/api/library/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{@base_url}/api/library"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(options)
    url = "#{@base_url}/api/library"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, options)
    url = "#{@base_url}/api/library/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def toggle_featured(id, params={}, payload={})
    url = "#{@base_url}/api/library/#{id}/toggle-featured"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, payload={})
    url = "#{@base_url}/api/library/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  # NOT json, multipart file upload
  def update_logo(id, logo_file, dark_logo_file=nil)
    url = "#{@base_url}/api/library/#{id}/update-logo"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    # payload["instanceType"] = {}
    if logo_file
      # payload["instanceType"]["logo"] = logo_file
      payload["logo"] = logo_file
    end
    if dark_logo_file
      # payload["instanceType"]["darkLogo"] = dark_logo_file
      payload["darkLogo"] = dark_logo_file
    end
    if logo_file.is_a?(File) || dark_logo_file.is_a?(File)
      payload[:multipart] = true
    else
      headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

end
