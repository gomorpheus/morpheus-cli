require 'morpheus/api/rest_interface'

class Morpheus::PluginsInterface < Morpheus::RestInterface

  def base_path
    "/api/plugins"
  end

  # upload a file with content-type: multipart
  def upload(local_file, params={}, headers={})
    url = "#{base_path}/upload"
    payload = {}
    payload[:multipart] = true
    payload["plugin"] = local_file
    execute(method: :post, url: url, params: params, payload: payload, headers: headers, timeout: 172800)
  end

  def check_updates(payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/check-updates", params: params, payload: payload, headers: headers)
  end

end
