require 'morpheus/api/rest_interface'

class Morpheus::BackupJobsInterface < Morpheus::RestInterface

  def base_path
    "/api/backups/jobs"
  end

end
