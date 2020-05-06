require 'morpheus/api/api_client'

class Morpheus::InvoiceLineItemsInterface < Morpheus::APIClient

  def list(params={})
    execute(method: :get, url: "/api/invoice-line-items", headers: {params: params})
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    execute(method: :get, url: "/api/invoice-line-items/#{id}", headers: {params: params})
  end

end
