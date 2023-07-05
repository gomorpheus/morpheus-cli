require 'morpheus/api/api_client'

class Morpheus::BackupRestoresInterface < Morpheus::APIClient

  def base_path
    "/api/backups/restores"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

  def destroy(id, params = {}, headers={})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, headers: headers)
  end

end
