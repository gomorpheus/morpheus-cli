require 'morpheus/api/read_interface'

class Morpheus::NetworkSecurityServerTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/networks/security-server-types"
  end

end
