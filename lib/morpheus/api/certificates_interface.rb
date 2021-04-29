require 'morpheus/api/rest_interface'

class Morpheus::CertificatesInterface < Morpheus::RestInterface

  def base_path
    "/api/certificates"
  end

end
