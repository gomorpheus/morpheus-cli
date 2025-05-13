require 'morpheus/api/api_client'

class Morpheus::NetworkFloatingIpsInterface < Morpheus::APIClient

  def base_path
    "/api/networks/floating-ips"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  # def create(payload, params={}, headers={})
  #   execute(method: :post, url: "#{base_path}", params: params, payload: payload, headers: headers)
  # end

  # def update(id, payload, params={}, headers={})
  #   validate_id!(id)
  #   execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, payload: payload, headers: headers)
  # end

  def destroy(id, params = {}, headers={})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  def release(id, payload={}, params={}, headers={})
    validate_id!(id)
  	execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}/release", params: params, payload: payload, headers: headers)
  end

  def allocate(payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/allocate", params: params, payload: payload, headers: headers)
  end
end
