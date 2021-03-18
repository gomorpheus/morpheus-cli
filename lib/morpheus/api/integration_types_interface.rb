require 'morpheus/api/read_interface'

class Morpheus::IntegrationTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/integration-types"
  end

end
