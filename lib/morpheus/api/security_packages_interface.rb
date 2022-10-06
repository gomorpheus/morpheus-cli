require 'morpheus/api/rest_interface'

class Morpheus::SecurityPackagesInterface < Morpheus::RestInterface

  def base_path
    "/api/security-packages"
  end

end
