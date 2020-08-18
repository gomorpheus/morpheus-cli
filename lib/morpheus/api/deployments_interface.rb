require 'morpheus/api/rest_interface'

class Morpheus::DeploymentsInterface < Morpheus::RestInterface

  def base_path
    "/api/deployments"
  end

  def list_versions(deployment_id, params={})
    execute(method: :get, url: "#{base_path}/#{deployment_id}/versions", params: params)
  end

  def get_version(deployment_id, id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{deployment_id}/versions/#{id}", params: params)
  end

  def create_version(deployment_id, payload, params={})
    execute(method: :post, url: "#{base_path}/#{deployment_id}/versions", params: params, payload: payload.to_json)
  end

  def update_version(deployment_id, id, payload, params={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{deployment_id}/versions/#{id}", params: params, payload: payload.to_json)
  end

  def destroy_version(deployment_id, id, params = {})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{deployment_id}/versions/#{id}", params: params)
  end

  def list_files(deployment_id, id, params={})
    execute(method: :get, url: "#{base_path}/#{deployment_id}/versions/#{id}/files", params: params)
  end

  # upload a file without multipart
  # local_file is the full absolute local filename
  # destination should be the full remote file path, including the file name.
  def upload_file(deployment_id, id, local_file, destination, params={})
    if destination.empty? || destination == "/" || destination == "." || destination.include?("../")
      raise "#{self.class}.upload_file() passed a bad destination: '#{destination}'"
    end
    url = "#{@base_url}/#{base_path}/#{deployment_id}/versions/#{id}/files"
    if !destination.to_s.empty?
      url += "/#{destination}"
    end
    # use URI to escape path
    uri = URI.parse(url)
    url = uri.path
    # params[:filename] = File.basename(destination)
    if !local_file.kind_of?(File)
      local_file = File.new(local_file, 'rb')
    end
    payload = local_file
    headers = {'Content-Type' => 'application/octet-stream'}
    headers['Content-Length'] = local_file.size # File.size(local_file)
    execute(method: :post, url: url, headers: headers, payload: payload, params: params, timeout: 172800)
  end

end
