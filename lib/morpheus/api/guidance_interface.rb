require 'morpheus/api/api_client'

class Morpheus::GuidanceInterface < Morpheus::APIClient

  def base_path
    "/api/guidance"
  end

  def list(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def stats()
    url = "#{base_path}/stats"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def types()
    url = "#{base_path}/types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id, params={})
    url = "#{base_path}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def exec(id, params={})
    url = "#{base_path}/#{id}/execute"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers)
  end

  def ignore(id, params={})
    url = "#{base_path}/#{id}/ignore"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers)
  end
end
