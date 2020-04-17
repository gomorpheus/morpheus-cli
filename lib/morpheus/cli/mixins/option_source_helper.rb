require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for fetching objects via /api/options/:optionSource
# The including class must establish @options_interface or @api_client
# This is useful for when the user does not need to have permission to other endpoints
module Morpheus::Cli::OptionSourceHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def options_interface
    api_interface = @options_interface
    api_interface = @api_client.options if api_interface.nil? && @api_client
    # @api_client.options
    raise "#{self.class} has not defined @options_interface or @api_client" if api_interface.nil?
    api_interface
  end

  def get_available_user_options(refresh=false)
    if !@available_user_options || refresh
      option_results = options_interface.options_for_source('users',{})
        @available_user_options = option_results['data'].collect {|it|
          {"name" => it["name"], "value" => it["value"],
            "username" => it["name"], "id" => it["value"]}
        }
    end
    return @available_user_options
  end

  def find_available_user_option(name)
    users = get_available_user_options().select {|it| 
      name && (it['name'].to_s == name.to_s || it['value'].to_s == name.to_s) }
    if users.empty?
      print_red_alert "User not found by username or id '#{name}'"
      return nil
    elsif users.size > 1
      print_red_alert "#{users.size} users found by username or id '#{name}'"
      return nil
    else
      return users[0]
    end
  end


  def get_group_options(refresh=false, api_params={})
    if !@available_group_options || refresh
      option_results = options_interface.options_for_source('groups', api_params)
        @available_group_options = option_results['data'].collect {|it|
          {"name" => it["name"], "value" => it["value"], "id" => it["value"]}
        }
    end
    return @available_group_options
  end

  def find_group_option(group_id, refresh=false, api_params={})
    if group_id.to_s.strip == ""
      print_red_alert "Group not found by for blank id"
      return nil
    end
    groups = get_group_options(refresh, api_params).select {|it| (it['name'].to_s == group_id.to_s || it['id'].to_s == group_id.to_s) }
    if groups.empty?
      print_red_alert "Group not found by '#{group_id}'"
      return nil
    elsif groups.size > 1
      print_red_alert "#{groups.size} groups found by '#{group_id}'"
      return nil
    else
      return groups[0]
    end
  end

  def get_cloud_options(refresh=false, api_params={})
    if !@available_cloud_options || refresh
      option_results = options_interface.options_for_source('clouds', api_params)
        @available_cloud_options = option_results['data'].collect {|it|
          {"name" => it["name"], "value" => it["value"], "id" => it["value"]}
        }
    end
    return @available_cloud_options
  end

  def find_cloud_option(cloud_id, refresh=false, api_params={})
    if cloud_id.to_s.strip == ""
      print_red_alert "Cloud not found by for blank id"
      return nil
    end
    clouds = get_cloud_options(refresh, api_params).select {|it| (it['name'].to_s == cloud_id.to_s || it['id'].to_s == cloud_id.to_s) }
    if clouds.empty?
      print_red_alert "Cloud not found by '#{cloud_id}'"
      return nil
    elsif clouds.size > 1
      print_red_alert "#{clouds.size} clouds found by '#{cloud_id}'"
      return nil
    else
      return clouds[0]
    end
  end

  # todo: some other common ones, accounts (tenants), groups, clouds

end
