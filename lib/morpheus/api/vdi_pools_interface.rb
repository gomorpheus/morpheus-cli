require 'morpheus/api/rest_interface'

class Morpheus::VdiPoolsInterface < Morpheus::RestInterface

  def base_path
    "/api/vdi-pools"
  end

  # NOT json, multipart file upload
  def update_logo(id, logo_file)
    url = "#{base_path}/#{id}/update-logo"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload[:logo] = logo_file
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

end
