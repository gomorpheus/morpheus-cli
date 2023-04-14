require 'morpheus/api/rest_interface'

class Morpheus::BackupsInterface < Morpheus::RestInterface

  def base_path
    "/api/backups"
  end

  def create_options(payload, params={}, headers={})
    execute(method: :post, url: "#{base_path}/create", params: params, payload: payload, headers: headers)
  end

  def summary(params={})
    execute(method: :get, url: "#{base_path}/summary", params: params)
  end

  def history(params={})
    execute(method: :get, url: "#{base_path}/history", params: params)
  end
end
