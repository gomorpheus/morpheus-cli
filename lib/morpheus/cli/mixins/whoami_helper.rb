require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for fetching and printing whoami information
module Morpheus::Cli::WhoamiHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def load_whoami(refresh=false)
    appliance = @remote_appliance # from establish_connection()
    if appliance.nil?
      print_red_alert "No current appliance. See `remote use`."
      exit 1
    end
    # fetch from cache first
    whoami_response = nil
    cached_response = ::Morpheus::Cli::Whoami.load_whoami(appliance[:name], appliance[:username], refresh)
    if cached_response
      whoami_response = cached_response
    else
      whoami_interface = @whoami_interface || @api_client.whoami
      whoami_response = whoami_interface.get()
      # save the result to the cache
      ::Morpheus::Cli::Whoami.save_whoami(appliance[:name], appliance[:username], whoami_response)
    end

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

  def current_account
    if @current_user.nil?
      load_whoami
    end
    @current_user ? @current_user['account'] : nil
  end

  def is_master_account
    if @current_user.nil?
      load_whoami
    end
    @is_master_account
  end

  def current_user
    if @current_user.nil?
      load_whoami
    end
    @current_user
  end

  def current_user_permissions
    if @user_permissions.nil?
      load_whoami
    end
    @user_permissions
  end

end
