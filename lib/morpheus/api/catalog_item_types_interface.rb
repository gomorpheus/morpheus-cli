require 'morpheus/api/rest_interface'

class Morpheus::CatalogItemTypesInterface < Morpheus::RestInterface

  def base_path
    "/api/catalog-item-types"
  end

  # NOT json, multipart file upload
  # def update_logo(id, logo_file)
  #   url = "#{base_path}/#{id}/update-logo"
  #   headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
  #   payload = {}
  #   payload[:logo] = logo_file
  #   payload[:multipart] = true
  #   execute(method: :post, url: url, headers: headers, payload: payload)
  # end

  # NOT json, multipart file upload, uses PUT update endpoint
  def update_logo(id, logo_file)
    url = "#{base_path}/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload["catalogItemType"] = {"logo" => logo_file}
    payload[:multipart] = true
    execute(method: :put, url: url, headers: headers, payload: payload)
  end

end
