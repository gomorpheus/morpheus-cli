require 'morpheus/api/api_client'
class Morpheus::ArchiveFilesInterface < Morpheus::APIClient

  def get(file_id, params={})
    raise "#{self.class}.get() passed a blank id!" if file_id.to_s == ''
    url = "#{@base_url}/api/archives/files/#{file_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  # full_file_path is $bucketName/$filePath
  def download_file_by_path(full_file_path, params={})
    raise "#{self.class}.download_file_by_path() passed a blank file path!" if full_file_path.to_s == ''
    url = "#{@base_url}/api/archives/download" + "/#{full_file_path}".squeeze('/')
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers, timeout: 172800}
    execute(opts, {parse_json: false})
  end

  def download_file_by_path_chunked(full_file_path, outfile, params={})
    raise "#{self.class}.download_file_by_path_chunked() passed a blank file path!" if full_file_path.to_s == ''
    url = "#{@base_url}/api/archives/download" + "/#{full_file_path}".squeeze('/')
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers, timeout: 172800}
    # execute(opts, {parse_json: false})
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
    return http_response
  end

  def download_public_file_by_path_chunked(full_file_path, outfile, params={})
    raise "#{self.class}.download_public_file_by_path_chunked() passed a blank file path!" if full_file_path.to_s == ''
    url = "#{@base_url}/public-archives/download" + "/#{full_file_path}".squeeze('/')
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers, timeout: 172800}
    # execute(opts, {parse_json: false})
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
    return http_response
  end

  def download_file_by_link_chunked(link_key, outfile, params={})
    raise "#{self.class}.download_file_by_link_chunked() passed a blank file path!" if full_file_path.to_s == ''
    url = "#{@base_url}/public-archives/link"
    params['s'] = link_key
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers, timeout: 172800}
    # execute(opts, {parse_json: false})
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
    return http_response
  end

  def history(file_id, params={})
    raise "#{self.class}.history() passed a blank id!" if file_id.to_s == ''
    url = "#{@base_url}/api/archives/files/#{file_id}/history"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list_links(file_id, params={})
    raise "#{self.class}.links() passed a blank id!" if file_id.to_s == ''
    url = "#{@base_url}/api/archives/files/#{file_id}/links"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create_file_link(file_id, params={})
    url = "#{@base_url}/api/archives/files/#{file_id}/links"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers}
    execute(opts)
  end

  def download_file_link(link_key, params={})
  end

  def destroy_file_link(file_id, link_id, params={})
    url = "#{@base_url}/api/archives/files/#{file_id}/links/#{link_id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  # for now upload() and list_files() are available in ArchiveBucketsInterface
  # the url is like /api/archives/buckets/$id/files

  # def list(params={})
  #   url = "#{@base_url}/api/archives/files"
  #   headers = { params: params, authorization: "Bearer #{@access_token}" }
  #   opts = {method: :get, url: url, headers: headers}
  #   execute(opts)
  # end

  # def create(payload)
  #   url = "#{@base_url}/api/archives/files"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  # def update(id, payload)
  #   url = "#{@base_url}/api/archives/files/#{id}"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
  #   execute(opts)
  # end

  def destroy(id, params={})
    url = "#{@base_url}/api/archives/files/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

end
