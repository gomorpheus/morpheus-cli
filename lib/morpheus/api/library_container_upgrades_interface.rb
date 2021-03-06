require 'morpheus/api/api_client'

class Morpheus::LibraryContainerUpgradesInterface < Morpheus::APIClient

  def get(instance_type_id, id, params={})
    #raise "#{self.class}.get() passed a blank instance_type_id!" if instance_type_id.to_s == ''
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = build_url(instance_type_id, id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(instance_type_id, params={})
    url = build_url(instance_type_id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(instance_type_id, options)
    url = build_url(instance_type_id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(instance_type_id, id, options)
    url = build_url(instance_type_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(instance_type_id, id, payload={})
    url = build_url(instance_type_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  private

  def build_url(instance_type_id=nil, id=nil)
    url = "#{@base_url}/api"
    if instance_type_id
      url += "/library/#{instance_type_id}/upgrades"
    else
      url += "/library/upgrades" # this api route does not exist yet
    end
    if id
      url += "/#{id}"
    end
    url
  end


end
