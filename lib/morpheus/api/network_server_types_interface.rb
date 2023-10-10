require 'morpheus/api/read_interface'

class Morpheus::NetworkServerTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/networks/server-types"
  end

end
