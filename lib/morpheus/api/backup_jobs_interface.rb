require 'morpheus/api/rest_interface'

class Morpheus::BackupJobsInterface < Morpheus::RestInterface

  def base_path
    "/api/backups/jobs"
  end

  def execute_job(id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(id.to_s)}/execute", params: params, payload: payload, headers: headers)
  end

end
