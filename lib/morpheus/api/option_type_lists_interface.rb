require 'morpheus/api/api_client'

class Morpheus::OptionTypeListsInterface < Morpheus::APIClient

  def base_path
    "/api/library/option-type-lists"
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{base_path}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{base_path}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(params)
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list_items(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{base_path}/#{id}/items"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{base_path}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{base_path}/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id)
    url = "#{base_path}/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end
end
