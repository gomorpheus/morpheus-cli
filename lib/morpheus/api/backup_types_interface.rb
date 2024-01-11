require 'morpheus/api/read_interface'

class Morpheus::BackupTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/backup-types"
  end

end