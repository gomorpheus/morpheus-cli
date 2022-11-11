require 'morpheus/api/rest_interface'

class Morpheus::IntegrationsInterface < Morpheus::RestInterface

  def base_path
    "/api/integrations"
  end

  def refresh(id, params={}, payload={}, headers={})
    validate_id!(id)
    execute(method: :post, url: "#{base_path}/#{id}/refresh", params: params, payload: payload, headers: headers)
  end

  ## Integration Objects CRUD

  def list_objects(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/objects", params: params, headers: headers)
  end

  def get_object(id, obj_id, params={}, headers={})
    validate_id!(id)
    validate_id!(obj_id)
    execute(method: :get, url: "#{base_path}/#{id}/objects/#{obj_id}", params: params, headers: headers)
  end

  def create_object(id, payload, params={}, headers={})
    validate_id!(id)
    execute(method: :post, url: "#{base_path}/#{id}/objects", params: params, payload: payload, headers: headers)
  end

  def update_object(id, obj_id, payload, params={}, headers={})
    validate_id!(id)
    validate_id!(obj_id)
    execute(method: :put, url: "#{base_path}/#{id}/objects/#{obj_id}", params: params, payload: payload, headers: headers)
  end

  def destroy_object(id, obj_id, params = {}, headers={})
    validate_id!(id)
    validate_id!(obj_id)
    execute(method: :delete, url: "#{base_path}/#{id}/objects/#{obj_id}", params: params, headers: headers)
  end

  ## Integration Inventory Item CRUD

  def list_inventory(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/inventory", params: params, headers: headers)
  end

  def get_inventory(id, inventory_id, params={}, headers={})
    validate_id!(id)
    validate_id!(inventory_id)
    execute(method: :get, url: "#{base_path}/#{id}/inventory/#{inventory_id}", params: params, headers: headers)
  end

  # def create_inventory(id, payload, params={}, headers={})
  #   validate_id!(id)
  #   execute(method: :post, url: "#{base_path}/#{id}/inventory", params: params, payload: payload, headers: headers)
  # end

  def update_inventory(id, inventory_id, payload, params={}, headers={})
    validate_id!(id)
    validate_id!(inventory_id)
    execute(method: :put, url: "#{base_path}/#{id}/inventory/#{inventory_id}", params: params, payload: payload, headers: headers)
  end

  # def destroy_inventory(id, inventory_id, params = {}, headers={})
  #   validate_id!(id)
  #   validate_id!(inventory_id)
  #   execute(method: :delete, url: "#{base_path}/#{id}/inventory/#{inventory_id}", params: params, headers: headers)
  # end

end
