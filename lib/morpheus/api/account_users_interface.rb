require 'morpheus/api/rest_interface'

class Morpheus::AccountUsersInterface < Morpheus::RestInterface

  def base_path(account_id)
    if account_id
      "/api/accounts/#{account_id}/users"
    else
      "/api/users"
    end
  end

  def list(account_id, params={}, headers={})
    #validate_id!(account_id, "account_id")
    execute(method: :get, url: "#{build_url(account_id)}", params: params, headers: headers)
  end

  def get(account_id, id, params={}, headers={})
    #validate_id!(account_id, "account_id")
    validate_id!(id)
    execute(method: :get, url: "#{build_url(account_id, id)}", params: params, headers: headers)
  end

  def create(account_id, payload, params={}, headers={})
    #validate_id!(account_id, "account_id")
    execute(method: :post, url: "#{build_url(account_id)}", params: params, payload: payload, headers: headers)
  end

  def update(account_id, id, payload, params={}, headers={})
    #validate_id!(account_id, "account_id")
    validate_id!(id)
    execute(method: :put, url: "#{build_url(account_id, id)}", params: params, payload: payload, headers: headers)
  end

  def destroy(account_id, id, params = {}, headers={})
    #validate_id!(account_id, "account_id")
    validate_id!(id)
    execute(method: :delete, url: "#{build_url(account_id, id)}", params: params, headers: headers)
  end

  def feature_permissions(account_id, id, params={}, headers={})
    #validate_id!(account_id, "account_id")
    validate_id!(id)
    execute(method: :get, url: "#{build_url(account_id, id)}/feature-permissions", params: params, headers: headers)
  end

  def permissions(account_id, id, params={}, headers={})
    #validate_id!(account_id, "account_id")
    validate_id!(id)
    execute(method: :get, url: "#{build_url(account_id, id)}/permissions", params: params, headers: headers)
  end

  def available_roles(account_id, id=nil, params={}, headers={})
    #validate_id!(account_id, "account_id")
    execute(method: :get, url: "#{build_url(account_id, id)}/available-roles", params: params, headers: headers)
  end

  private

  def build_url(account_id, id=nil)
    url = base_path(account_id)
    if id
      url += "/#{CGI::escape(id.to_s)}"
    end
    url
  end

end
