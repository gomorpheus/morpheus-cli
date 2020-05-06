require 'morpheus/api/api_client'

class Morpheus::InvoicesInterface < Morpheus::APIClient

  def list(params={})
    execute(method: :get, url: "/api/invoices", headers: {params: params})
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    execute(method: :get, url: "/api/invoices/#{id}", headers: {params: params})
  end

  def refresh(params={}, payload={})
    headers = {:params => params, 'Content-Type' => 'application/json'}
    execute(method: :post, url: "/api/invoices/refresh", headers: headers, payload: payload.to_json)
  end

end
