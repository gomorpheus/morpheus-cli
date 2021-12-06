require 'morpheus/api/api_client'

# Interface class to be subclassed by interfaces that provide CRUD endpoints
# for objects underneath another resource
# Subclasses must override the base_path(resource_id) method
class Morpheus::SecondaryReadInterface < Morpheus::APIClient

  # subclasses should override in your interface
  # Example: "/api/things/#{resource_id}/widgets"
  def base_path(resource_id)
    raise "#{self.class} has not defined base_path(resource_id)!"
  end

  def list(resource_id, params={}, headers={})
    validate_id!(resource_id)
    execute(method: :get, url: "#{base_path(resource_id)}", params: params, headers: headers)
  end

  def get(resource_id, id, params={}, headers={})
    validate_id!(resource_id)
    validate_id!(id)
    execute(method: :get, url: "#{base_path(resource_id)}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

end
