require 'morpheus/api/rest_interface'

class Morpheus::StorageServersInterface < Morpheus::RestInterface

  def base_path
    "/api/storage-servers"
  end

end
