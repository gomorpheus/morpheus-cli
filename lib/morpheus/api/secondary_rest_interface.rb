require 'morpheus/api/api_client'

# Interface class to be subclassed by interfaces that provide CRUD endpoints
# for objects underneath another resource
# Subclasses must override the base_path(parent_id) method
class Morpheus::SecondaryRestInterface < Morpheus::APIClient

  # subclasses should override in your interface
  # Example: "/api/things/#{parent_id}/widgets"
  def base_path(parent_id)
    raise "#{self.class} has not defined base_path(parent_id)!"
  end

  def list(parent_id, params={}, headers={})
    validate_id!(parent_id)
    execute(method: :get, url: "#{base_path(parent_id)}", params: params, headers: headers)
  end

  def get(parent_id, id, params={}, headers={})
    validate_id!(parent_id)
    validate_id!(id)
    execute(method: :get, url: "#{base_path(parent_id)}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  def create(parent_id, payload, params={}, headers={})
    validate_id!(parent_id)
    execute(method: :post, url: "#{base_path(parent_id)}", params: params, payload: payload, headers: headers)
  end

  def update(parent_id, id, payload, params={}, headers={})
    validate_id!(parent_id)
    validate_id!(id)
    execute(method: :put, url: "#{base_path(parent_id)}/#{CGI::escape(id.to_s)}", params: params, payload: payload, headers: headers)
  end

  def destroy(parent_id, id, params = {}, headers={})
    validate_id!(parent_id)
    validate_id!(id)
    execute(method: :delete, url: "#{base_path(parent_id)}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

end
