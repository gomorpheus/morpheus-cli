require 'morpheus/api/api_client'

class Morpheus::DocInterface < Morpheus::APIClient

  def list(params={})
    url = "/api/doc"
    headers = {params: params}
    execute(method: :get, url: url, headers: headers)
  end

  def openapi(params={})
    url = "/api/doc/openapi"
    fmt = params.delete('format')
    if fmt
      url = url + "." + fmt
    end
    is_yaml = fmt == "yml" || fmt == "yaml"
    headers = {params: params}
    execute(method: :get, url: url, headers: headers, timeout: 172800, parse_json: !is_yaml)
  end

  def download_openapi(outfile, params={})
    # note that RestClient.execute still requires the full path with base_url
    url = "#{@base_url}/api/doc/openapi"
    fmt = params.delete('format')
    if fmt
      url = url + "." + fmt
    end
    headers = {params: params, authorization: "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers, timeout: 172800, parse_json: false}

    if @dry_run
      return opts
    end

    http_response = nil
    File.open(File.expand_path(outfile), 'w') {|f|
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
