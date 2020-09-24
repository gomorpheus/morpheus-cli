require 'morpheus/cli/mixins/print_helper'
# Mixin for Morpheus::Cli command classes
# Provides common methods for infrastructure management
module Morpheus::Cli::DeploymentsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  ## Deployments

  def deployments_interface
    raise "#{self.class} has not defined @deployments_interface" if @deployments_interface.nil?
    @deployments_interface
  end

  def deployment_object_key
    'deployment'
  end

  def deployment_list_key
    'deployments'
  end

  def find_deployment_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_deployment_by_id(val)
    else
      return find_deployment_by_name(val)
    end
  end

  def find_deployment_by_id(id)
    begin
      json_response = deployments_interface.get(id.to_i)
      return json_response[deployment_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Deployment not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_deployment_by_name(name)
    json_response = deployments_interface.list({name: name.to_s})
    deployments = json_response[deployment_list_key]
    if deployments.empty?
      print_red_alert "Deployment not found by name '#{name}'"
      return nil
    elsif deployments.size > 1
      print_red_alert "#{deployments.size} deployments found by name '#{name}'"
      puts_error as_pretty_table(deployments, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return deployments[0]
    end
  end


  ## Deployment Types

  # unused?
  def find_deployment_type_by_name(val)
    raise "find_deployment_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
    results = @deployments_interface.deployment_types(val)
    result = nil
    if !results['deploymentTypes'].nil? && !results['deploymentTypes'].empty?
      result = results['deploymentTypes'][0]
    elsif val.to_i.to_s == val
      results = @deployments_interface.deployment_types(val.to_i)
      result = results['deploymentType']
    end
    if result.nil?
      print_red_alert "Deployment Type not found by '#{val}'"
      return nil
    end
    return result
  end

  ## Deployment Versions

  def deployment_version_object_key
    # 'deploymentVersion'
    'version'
  end

  def deployment_version_list_key
    # 'deploymentVersions'
    'versions'
  end

  def find_deployment_version_by_name_or_id(deployment_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_deployment_version_by_id(deployment_id, val)
    else
      return find_deployment_version_by_name(deployment_id, val)
    end
  end

  def find_deployment_version_by_id(deployment_id, id)
    begin
      json_response = deployments_interface.get_version(deployment_id, id.to_i)
      return json_response[deployment_version_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Deployment version not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_deployment_version_by_name(deployment_id, name)
    json_response = deployments_interface.list_versions(deployment_id, {userVersion: name.to_s})
    deployment_versions = json_response[deployment_version_list_key]
    if deployment_versions.empty?
      print_red_alert "Deployment version not found by version '#{name}'"
      return nil
    elsif deployment_versions.size > 1
      print_red_alert "#{deployment_versions.size} deployment versions found by version '#{name}'"
      puts_error as_pretty_table(deployment_versions, {"ID" => 'id', "VERSION" => 'userVersion'}, {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return deployment_versions[0]
    end
  end

end
