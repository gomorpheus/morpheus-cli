require 'morpheus/api/rest_interface'

class Morpheus::SecurityScansInterface < Morpheus::RestInterface

  def base_path
    "/api/security-scans"
  end

end
