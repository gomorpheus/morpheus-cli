require 'morpheus/api/api_client'

class Morpheus::ProcessesInterface < Morpheus::APIClient

  def base_path
    "/api/processes"
  end

  def list(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{base_path}/#{CGI::escape(id.to_s)}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get_event(event_id, params={})
    raise "#{self.class}.get() passed a blank event id!" if event_id.to_s == ''
    url = "#{base_path}/events/#{CGI::escape(event_id.to_s)}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def retry(id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(id.to_s)}/retry", params: params, payload: payload, headers: headers)
  end

  def cancel(id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(id.to_s)}/cancel", params: params, payload: payload, headers: headers)
  end

end
