require 'morpheus/api/read_interface'

class Morpheus::InvoiceLineItemsInterface < Morpheus::ReadInterface

  def base_path
    "/api/invoice-line-items"
  end

end
