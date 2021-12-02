require 'morpheus/api/read_interface'

class Morpheus::StorageVolumeTypesInterface < Morpheus::ReadInterface

  def base_path
    "/api/storage-volume-types"
  end

end
