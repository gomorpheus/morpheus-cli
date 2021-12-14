require 'morpheus/api/rest_interface'

class Morpheus::UsersInterface < Morpheus::RestInterface

  def base_path
    "/api/users"
  end

  def feature_permissions(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/feature-permissions", params: params, headers: headers)
  end

  def permissions(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/permissions", params: params, headers: headers)
  end

  def available_roles(id=nil, params={}, headers={})
    execute(method: :get, url: "#{build_url(id)}/available-roles", params: params, headers: headers)
  end

  private

  def build_url(id=nil)
    url = base_path
    if id
      url += "/#{id}"
    end
    url
  end

end
