require 'morpheus/api/api_client'

class Morpheus::WhitelabelSettingsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil, api='whitelabel-settings')
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @api_url = "#{base_url}/api/#{api}"
    @expires_at = expires_at
  end

  def get(params={})
    url = @api_url
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = @api_url
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_images(payload, params={})
    url = "#{@api_url}/images"
    headers = { params: params, :authorization => "Bearer #{@access_token}" }
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def reset_image(image_type, params={})
    url = "#{@api_url}/images/#{image_type}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def download_image(image_type, outfile, params={})
    url = "#{@api_url}/images/#{image_type}"
    headers = { params: params, :authorization => "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers, timeout: 172800}

    if @dry_run
      return opts
    end

    http_response = nil
    File.open(outfile, 'w') {|f|
      block = proc { |response|
        response.read_body do |chunk|
          # writing to #{outfile} ..."
          f.write chunk
        end
      }
      opts[:block_response] = block
      http_response = Morpheus::RestClient.execute(opts)
    }
    http_response
  end

end
