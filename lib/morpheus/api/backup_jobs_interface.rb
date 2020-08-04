require 'morpheus/api/api_client'

class Morpheus::BackupJobsInterface < Morpheus::RestInterface

  def base_path
    "/api/backups/jobs"
  end

end
