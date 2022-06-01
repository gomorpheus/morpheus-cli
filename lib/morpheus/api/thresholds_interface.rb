require 'morpheus/api/rest_interface'

class Morpheus::ThresholdsInterface < Morpheus::RestInterface

  def base_path
    "/api/thresholds"
  end

end
