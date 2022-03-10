require 'morpheus/api/rest_interface'

class Morpheus::CredentialsInterface < Morpheus::RestInterface

  def base_path
    "/api/credentials"
  end

end
