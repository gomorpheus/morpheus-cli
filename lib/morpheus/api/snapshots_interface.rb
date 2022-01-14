require 'morpheus/api/api_client'

# Snapshots API interface.
class Morpheus::SnapshotsInterface < Morpheus::APIClient

  def get(snapshot_id)
    url = "#{@base_url}/api/snapshots/#{snapshot_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def remove(snapshot_id, payload={})
    url = "#{@base_url}/api/snapshots/#{snapshot_id}"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end
end
