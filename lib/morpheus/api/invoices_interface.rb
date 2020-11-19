require 'morpheus/api/api_client'

class Morpheus::InvoicesInterface < Morpheus::APIClient

  def base_path
    "/api/invoices"
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", headers: {params: params})
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    execute(method: :get, url: "#{base_path}/#{id}", headers: {params: params})
  end

  def update(id, payload)
    validate_id!(id)
    execute(url: "#{base_path}/#{id}", payload: payload.to_json, method: :put)
  end

  def refresh(params={}, payload={})
    headers = {:params => params, 'Content-Type' => 'application/json'}
    execute(method: :post, url: "#{base_path}/refresh", headers: headers, payload: payload.to_json)
  end

end
