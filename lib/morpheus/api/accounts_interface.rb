require 'morpheus/api/rest_interface'

class Morpheus::AccountsInterface < Morpheus::RestInterface

  def base_path
    "/api/accounts"
  end

end
