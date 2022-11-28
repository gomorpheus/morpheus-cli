require 'morpheus/api/api_client'
# require 'morpheus/api/monitoring_checks_interface'
# require 'morpheus/api/monitoring_groups_interface'
# require 'morpheus/api/monitoring_apps_interface'
# require 'morpheus/api/monitoring_incidents_interface'
# require 'morpheus/api/monitoring_contacts_interface'
# require 'morpheus/api/monitoring_alerts_interface'

class Morpheus::MonitoringInterface < Morpheus::APIClient

  def checks
    Morpheus::MonitoringChecksInterface.new(common_interface_options).setopts(@options)
  end

  def groups
    Morpheus::MonitoringGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def apps
    Morpheus::MonitoringAppsInterface.new(common_interface_options).setopts(@options)
  end

  def incidents
    Morpheus::MonitoringIncidentsInterface.new(common_interface_options).setopts(@options)
  end

  def contacts
    Morpheus::MonitoringContactsInterface.new(common_interface_options).setopts(@options)
  end

  def alerts
    Morpheus::MonitoringAlertsInterface.new(common_interface_options).setopts(@options)
  end
  
end
