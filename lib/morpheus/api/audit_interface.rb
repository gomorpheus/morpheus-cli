require 'morpheus/api/read_interface'

class Morpheus::AuditInterface < Morpheus::ReadInterface

  def base_path
    "/api/audit"
  end

end
