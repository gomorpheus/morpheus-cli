require 'morpheus/api/rest_interface'

class Morpheus::StorageVolumesInterface < Morpheus::RestInterface

  def base_path
    "/api/storage-volumes"
  end

end
