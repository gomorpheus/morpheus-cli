require 'morpheus/api/api_client'

class Morpheus::EmailTemplatesInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/email-templates"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    url = "#{@base_url}/api/email-templates/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{base_path}/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    execute(method: :get, url: url, headers: headers)
  end


  def update(id, payload)
    url = "#{@base_url}/api/email-templates/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end


  def create(options)
    url = "#{@base_url}/api/email-templates"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def template_types(params={})
    url = "#{@base_url}/api/email-templates/types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/email-templates/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

end