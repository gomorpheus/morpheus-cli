require 'morpheus/api/read_interface'

class Morpheus::NetworkPoolServerTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/networks/pool-server-types"
  end

end
