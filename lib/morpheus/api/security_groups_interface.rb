require 'morpheus/api/api_client'

class Morpheus::SecurityGroupsInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/security-groups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id, params={})
    url = "#{@base_url}/api/security-groups/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{url}/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{@base_url}/api/security-groups/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def delete(id)
    url = "#{@base_url}/api/security-groups/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def create_location(id, payload)
    url = "#{@base_url}/api/security-groups/#{id}/locations"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def delete_location(id, location_id, params={})
    url = "#{@base_url}/api/security-groups/#{id}/locations/#{location_id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

end
