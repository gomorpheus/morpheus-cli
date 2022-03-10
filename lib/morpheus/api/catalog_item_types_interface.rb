require 'morpheus/api/rest_interface'

class Morpheus::CatalogItemTypesInterface < Morpheus::RestInterface

  def base_path
    "/api/catalog-item-types"
  end

  # NOT json, multipart file upload, uses PUT update endpoint
  def update_logo(id, logo_file, dark_logo_file=nil)
    #url = "#{base_path}/#{id}/update-logo"
    url = "#{base_path}/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload["catalogItemType"] = {}
    if logo_file
      payload["catalogItemType"]["logo"] = logo_file
    end
    if dark_logo_file
      payload["catalogItemType"]["darkLogo"] = dark_logo_file
    end
    payload[:multipart] = true
    execute(method: :put, url: url, headers: headers, payload: payload)
  end

end
