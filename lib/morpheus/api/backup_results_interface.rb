require 'morpheus/api/api_client'

class Morpheus::BackupResultsInterface < Morpheus::APIClient

  def base_path
    "/api/backups/results"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  def cancel(id, payload={}, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, payload: payload, headers: headers)
  end

  def destroy(id, params = {}, headers={})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  def create_options(id, payload={}, params={}, headers={})
    validate_id!(id)
    execute(method: :post, url: "#{base_path}/#{CGI::escape(id.to_s)}/create-restore", params: params, payload: payload, headers: headers)
  end
end
