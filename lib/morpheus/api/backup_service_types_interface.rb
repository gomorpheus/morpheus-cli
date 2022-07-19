require 'morpheus/api/read_interface'

class Morpheus::BackupServiceTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/backup-service-types"
  end

end