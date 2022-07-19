require 'morpheus/api/rest_interface'

class Morpheus::BackupServicesInterface < Morpheus::RestInterface

  def base_path
    "/api/backup-services"
  end

end
