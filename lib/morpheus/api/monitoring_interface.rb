require 'morpheus/api/api_client'
require 'morpheus/api/checks_interface'
require 'morpheus/api/incidents_interface'
require 'morpheus/api/monitoring_contacts_interface'
require 'morpheus/api/monitoring_groups_interface'
require 'morpheus/api/monitoring_apps_interface'

class Morpheus::MonitoringInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def checks
    Morpheus::ChecksInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def incidents
    Morpheus::IncidentsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def contacts
    Morpheus::MonitoringContactsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def groups
    Morpheus::MonitoringGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def apps
    Morpheus::MonitoringAppsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end
  
end
