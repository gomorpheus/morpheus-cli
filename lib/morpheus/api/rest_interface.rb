require 'morpheus/api/api_client'

# Interface class to be subclassed by interfaces that provide CRUD endpoints
# Subclasses must override the base_path method
class Morpheus::RestInterface < Morpheus::APIClient

  # subclasses should override in your interface
  # Example: "/api/things"
  def base_path
    raise "#{self.class} has not defined base_path!" if @options[:base_path].nil?
    @options[:base_path]
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  def create(payload, params={}, headers={})
    execute(method: :post, url: "#{base_path}", params: params, payload: payload, headers: headers)
  end

  def update(id, payload, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, payload: payload, headers: headers)
  end

  def destroy(id, params = {}, headers={})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

end
