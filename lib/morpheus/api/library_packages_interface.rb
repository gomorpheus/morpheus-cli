require 'morpheus/api/api_client'

class Morpheus::LibraryPackagesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def download(params, outfile)
    url = "#{@base_url}/api/library/packages/download"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    # execute(opts, false)
    if Dir.exists?(outfile)
      raise "outfile is invalid. It is the name of an existing directory: #{outfile}"
    end
    # if @verify_ssl == false
    #   opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    # end
    if @dry_run
      return opts
    end
    http_response = nil
    bad_body = nil
    File.open(outfile, 'w') {|f|
      block = proc { |response|
        if response.code.to_i == 200
          response.read_body do |chunk|
              #puts "writing to #{outfile} ..."
              f.write chunk
          end
        else
          # puts_error (#{response.inspect}) #{chunk} ..."
          bad_body = response.body.to_s
        end
      }
      opts[:block_response] = block
      http_response = RestClient::Request.new(opts).execute
      # RestClient::Request.execute(opts)
    }
    return http_response, bad_body
  end

  def upload(file, params={})
    raise "implement this"
  end

end
