require 'morpheus/api/api_client'

class Morpheus::WhitelabelSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/whitelabel-settings"
  end

  def get(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = base_path
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_images(payload, params={})
    url = "#{base_path}/images"
    headers = { params: params, :authorization => "Bearer #{@access_token}" }
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def reset_image(image_type, params={})
    url = "#{base_path}/images/#{image_type}"
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def download_image(image_type, outfile, params={})
    url = "#{base_path}/images/#{image_type}"
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
