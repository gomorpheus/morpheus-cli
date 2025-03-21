require 'morpheus/api/api_client'

class Morpheus::ServerDevicesInterface < Morpheus::APIClient

  def base_path(server_id)
    "#{@base_url}/api/servers/#{server_id}"
  end

  # def get(server_id, id, params={})
  #   raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
  #   execute({method: :get, url: "#{base_path(server_id)}/devices/#{id}", params: params})
  # end

  def list(server_id, params={})
    execute({method: :get, url: "#{base_path(server_id)}/devices", params: params})
  end

  def assign(server_id, id, payload)
    execute({method: :put, url: "#{base_path(server_id)}/devices/#{id}/assign", payload: payload.to_json})
  end

  def attach(server_id, id, payload)
    execute({method: :put, url: "#{base_path(server_id)}/devices/#{id}/attach", payload: payload.to_json})
  end

  def detach(server_id, id, payload)
    execute({method: :put, url: "#{base_path(server_id)}/devices/#{id}/detach", payload: payload.to_json})
  end

end
