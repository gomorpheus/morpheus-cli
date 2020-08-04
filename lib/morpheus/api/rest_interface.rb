require 'morpheus/api/api_client'

class Morpheus::RestInterface < Morpheus::APIClient

  # subclasses should override in your interface
  # Example: "/api/things"
  def base_path
    raise "#{self.class} has not defined base_path!"
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

  def get(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params)
  end

  def create(payload, params={})
    execute(method: :post, url: "#{base_path}", params: params, payload: payload.to_json)
  end

  def update(id, payload, params={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{id}", params: params, payload: payload.to_json)
  end

  def destroy(id, params = {})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{id}", params: params)
  end

  protected

  def validate_id!(id)
    raise "#{self.class} passed a blank id!" if id.to_s.strip.empty?
  end

end
