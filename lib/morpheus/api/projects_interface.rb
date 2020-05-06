require 'morpheus/api/api_client'

class Morpheus::ProjectsInterface < Morpheus::APIClient

  def build_url(id=nil)
    id ? "/api/projects/#{id}" : "/api/projects"
  end

  def list(params={})
    execute(method: :get, url: build_url(), headers: {params: params})
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    execute(method: :get, url: build_url(id), headers: {params: params})
  end

  def create(payload, params={})
    # headers = {:params => params, 'Content-Type' => 'application/json'}
    headers = {:params => params, 'Content-Type' => 'application/json'}
    execute(method: :post, url: build_url(), headers: headers, payload: payload.to_json)
  end

  def update(id, payload, params={})
    headers = {:params => params, 'Content-Type' => 'application/json'}
    execute(method: :put, url: build_url(id), headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    execute(method: :delete, url: build_url(id), headers: {params: params})
  end

end
