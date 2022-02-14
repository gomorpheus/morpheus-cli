require 'morpheus/api/read_interface'

class Morpheus::CredentialTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/credential-types"
  end

end
