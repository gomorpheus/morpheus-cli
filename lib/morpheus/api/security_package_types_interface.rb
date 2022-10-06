require 'morpheus/api/read_interface'

class Morpheus::SecurityPackageTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/security-package-types"
  end

end
