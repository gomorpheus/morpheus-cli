require 'morpheus/api/api_client'

class Morpheus::LibraryContainerTypesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(layout_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = build_url(layout_id, id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(layout_id, params={})
    url = build_url(layout_id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(layout_id, options)
    url = build_url(layout_id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(layout_id, id, options)
    url = build_url(layout_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(layout_id, id, payload={})
    url = build_url(layout_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  private

  def build_url(layout_id=nil, id=nil)
    url = "#{@base_url}/api"
    if layout_id
      url += "/library/#{layout_id}/container-types"
    else
      url += "/library/container-types"
    end
    if id
      url += "/#{id}"
    end
    url
  end


end
