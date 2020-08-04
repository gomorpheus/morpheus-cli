require 'morpheus/api/api_client'

class Morpheus::BackupsInterface < Morpheus::RestInterface

  def base_path
    "/api/backups"
  end

  def summary(params={})
    execute(method: :get, url: "#{base_path}/summary", params: params)
  end

  def history(params={})
    execute(method: :get, url: "#{base_path}/history", params: params)
  end
end
