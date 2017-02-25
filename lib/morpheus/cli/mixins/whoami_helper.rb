require 'table_print'
require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes 
# Provides common methods for fetching and printing accounts, roles, and users.
# The including class must establish @accounts_interface, @roles_interface, @users_interface
module Morpheus::Cli::WhoamiHelper

	def self.included(klass)
		klass.send :include, Morpheus::Cli::PrintHelper
	end

	def load_whoami()
		whoami_interface = @whoami_interface || @api_client.whoami
		whoami_response = whoami_interface.get()
		# whoami_response = @whoami_interface.get()
		@current_user = whoami_response["user"] 
		if @current_user.empty?
			print_red_alert "Unauthenticated. Please login."
			exit 1
		end
		@is_master_account = whoami_response["isMasterAccount"]
		@user_permissions = whoami_response["permissions"]

		if whoami_response["appliance"]
			@appliance_build_verison = whoami_response["appliance"]["buildVersion"]
		else
			@appliance_build_verison = nil
		end

		return whoami_response
	end

end
