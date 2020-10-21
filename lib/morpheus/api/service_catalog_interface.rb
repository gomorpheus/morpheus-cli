require 'morpheus/api/api_client'
# Service Catalog Persona interface
class Morpheus::ServiceCatalogInterface < Morpheus::APIClient

  def base_path
    "/api/service-catalog"
  end

  # dashboard
  def dashboard(params={})
    execute(method: :get, url: "#{base_path}/dashboard", params: params)
  end

  # list catalog types available for ordering
  def list_types(params={})
    execute(method: :get, url: "#{base_path}/catalog", params: params)
  end

  # get specific catalog type
  def get_type(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/catalog/#{id}", params: params)
  end

  # list catalog inventory (items)
  def list_inventory(params={})
    execute(method: :get, url: "#{base_path}/inventory", params: params)
  end

  # get catalog inventory item
  def get_inventory(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/inventory/#{id}", params: params)
  end

  # delete a catalog inventory item
  def destroy_inventory(id, params = {})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/inventory/#{id}", params: params)
  end

  # get cart (one per user)
  def get_cart(params={})
    execute(method: :get, url: "#{base_path}/cart", params: params)
  end

  # update cart (set cart name)
  def update_cart(payload, params={})
    execute(method: :put, url: "#{base_path}/cart", params: params, payload: payload.to_json)
  end

  # validate a new item, can be used before before adding it
  def validate_cart_item(payload, params={})
    execute(method: :post, url: "#{base_path}/cart/items/validate", params: params, payload: payload.to_json)
  end

  # add item to cart
  def create_cart_item(payload, params={})
    execute(method: :post, url: "#{base_path}/cart/items", params: params, payload: payload.to_json)
  end

  # update item in the cart
  def update_cart_item(id, payload, params={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/cart/items/#{id}", params: params, payload: payload.to_json)
  end

  # remove item from the cart
  def destroy_cart_item(id, params={})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/cart/items/#{id}", params: params)
  end

  # place order with cart
  def checkout(payload, params={})
    execute(method: :post, url: "#{base_path}/checkout", params: params, payload: payload.to_json)
  end

  # remove all items from cart and reset name
  def clear_cart(params={})
    execute(method: :delete, url: "#{base_path}/cart", params: params)
  end

end
