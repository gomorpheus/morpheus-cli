require 'morpheus/api/api_client'
require 'net/http/post/multipart'
require 'mime/types'

class Morpheus::DeployInterface < Morpheus::APIClient

  def base_path
    # /api/deploys is now available in 5.0, switch to that eventually...
    "/api/deploy"
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

  def get(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params)
  end

  def create(instance_id, payload, params={})
    if instance_id
      execute(method: :post, url: "/api/instances/#{instance_id}/deploy", params: params, payload: payload.to_json)
    else
      execute(method: :post, url: "#{base_path}", params: params, payload: payload.to_json)
    end
  end

  def update(id, payload, params={})
    validate_id!(id)
    execute(url: "#{base_path}/#{id}", params: params, payload: payload.to_json, method: :put)
  end

  def destroy(id, params = {})
    validate_id!(id)
    execute(url: "#{base_path}/#{id}", params: params, method: :delete)
  end

  def deploy(id, payload, params = {})
    validate_id!(id)
    execute(url: "#{base_path}/#{id}/deploy", params: params, payload: payload.to_json, method: :post)
  end

end
