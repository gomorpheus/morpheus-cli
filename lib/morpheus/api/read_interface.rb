require 'morpheus/api/api_client'

# Interface class to be subclassed by interfaces that are read-only
# and only provide list() and get() methods, not full CRUD
# Subclasses must override the base_path method
class Morpheus::ReadInterface < Morpheus::APIClient

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

end
