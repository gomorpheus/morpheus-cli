require 'morpheus/api/api_client'
require 'uri'

class Morpheus::StorageProvidersInterface < Morpheus::APIClient

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/storage/buckets/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{@base_url}/api/storage/buckets"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/storage/buckets"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/storage/buckets/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/storage/buckets/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def list_files(id, file_path, params={})
    if file_path.to_s.strip == "/"
      file_path = ""
    end
    url = "#{@base_url}/api/storage/buckets/#{URI.escape(id.to_s)}" + "/files/#{URI.escape(file_path)}".squeeze('/')
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  # upload a file without multipart
  def upload_file(id, local_file, destination, params={})
    # puts "upload_file #{local_file} to destination #{destination}"
    # destination should be the full filePath, but the api looks like directory?filename=
    path = destination.to_s.squeeze("/")
    if !path || path == "" || path == "/" || path == "."
      raise "#{self.class}.upload_file() passed a bad destination: '#{destination}'"
    end
    if path[0].chr == "/"
      path = path[1..-1]
    end
    path_chunks = path.split("/")
    filename = path_chunks.pop
    safe_dirname = path_chunks.collect {|it| URI.escape(it) }.join("/")
    # filename = File.basename(destination)
    # dirname = File.dirname(destination)
    # if filename == "" || filename == "/"
    #   filename = File.basename(local_file)
    # end
    url = "#{@base_url}/api/storage/buckets/#{URI.escape(id.to_s)}" + "/files/#{safe_dirname}".squeeze('/')
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = filename # File.basename(destination)
    if !local_file.kind_of?(File)
      local_file = File.new(local_file, 'rb')
    end
    payload = local_file
    headers['Content-Length'] = local_file.size # File.size(local_file)
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def download_file(id, file_path, params={})
    raise "#{self.class}.download_file() passed a blank id!" if id.to_s == ''
    raise "#{self.class}.download_file() passed a blank file path!" if file_path.to_s == ''
    escaped_file_path = file_path.split("/").collect {|it| URI.escape(it) }.join("/")
    url = "#{@base_url}/api/storage/buckets/#{URI.escape(id.to_s)}" + "/download-file/#{escaped_file_path}".squeeze('/')
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts, false)
  end

  def download_file_chunked(id, file_path, outfile, params={})
    raise "#{self.class}.download_file() passed a blank id!" if id.to_s == ''
    raise "#{self.class}.download_file() passed a blank file path!" if file_path.to_s == ''
    escaped_file_path = file_path.split("/").collect {|it| URI.escape(it) }.join("/")
    url = "#{@base_url}/api/storage/buckets/#{URI.escape(id.to_s)}" + "/download-file/#{escaped_file_path}".squeeze('/')
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

  def download_zip_chunked(id, outfile, params={})
    #url = "#{@base_url}/api/storage/buckets/#{URI.escape(id.to_s)}" + ".zip"
    url = "#{@base_url}/api/storage/buckets/#{URI.escape(id.to_s)}/download-zip"
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

end
