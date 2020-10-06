require 'morpheus/api/rest_interface'

class Morpheus::SearchInterface < Morpheus::APIClient

  def base_path
    "/api/search"
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

end
