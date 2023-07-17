require 'morpheus/api/rest_interface'

class Morpheus::BackupsInterface < Morpheus::RestInterface

  def base_path
    "/api/backups"
  end

  def create_options(payload, params={}, headers={})
    execute(method: :post, url: "#{base_path}/create", params: params, payload: payload, headers: headers)
  end

  def summary(params={}, headers={})
    execute(method: :get, url: "#{base_path}/summary", params: params, headers: headers)
  end

  def execute_backup(id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(id.to_s)}/execute", params: params, payload: payload, headers: headers)
  end

end
