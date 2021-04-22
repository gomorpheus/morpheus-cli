require 'morpheus/api/read_interface'

class Morpheus::VdiAllocationsInterface < Morpheus::ReadInterface

  def base_path
    "/api/vdi-allocations"
  end

end
