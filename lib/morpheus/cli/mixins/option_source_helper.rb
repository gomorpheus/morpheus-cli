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

   # todo: rewrite these specific methods to use the generic one.
  
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
      name && (it['name'].to_s.downcase == name.to_s.downcase || it['value'].to_s == name.to_s) }
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

  def get_tenant_options(refresh=false, api_params={})
    if !@available_tenant_options || refresh
      # source should be 'tenants' or 'allTenants'
      # allTenants includes the current tenant
      # I think we should always use that so you can use your own id
      option_source = 'allTenants'
      option_results = options_interface.options_for_source(option_source, api_params)
        @available_tenant_options = option_results['data'].collect {|it|
          {"name" => it["name"], "value" => it["value"], "id" => it["value"]}
        }
    end
    return @available_tenant_options
  end

  def find_tenant_option(tenant_id, refresh=false, api_params={})
    tenant_id = tenant_id.to_s.strip
    tenant_id_downcase = tenant_id.to_s.downcase
    if tenant_id == ""
      print_red_alert "Tenant not found by for blank id"
      return nil
    end
    tenants = get_tenant_options(refresh, api_params).select {|it| (it['name'].to_s.downcase == tenant_id_downcase || it['id'].to_s == tenant_id.to_s) }
    if tenants.empty?
      print_red_alert "Tenant not found by '#{tenant_id}'"
      return nil
    elsif tenants.size > 1
      print_red_alert "#{tenants.size} tenants found by '#{tenant_id}'"
      return nil
    else
      return tenants[0]
    end
  end

  # parse cloud names or IDs into a name, works with array or csv
  # skips validation of ID for now, just worry about translating names/codes
  # def parse_cloud_id_list(id_list)
  #   cloud_ids = parse_id_list(id_list).collect {|cloud_id|
  #     if cloud_id.to_s =~ /\A\d{1,}\Z/
  #       cloud_id
  #     else
  #       cloud = find_cloud_option(cloud_id)
  #       if cloud.nil?
  #         # exit 1
  #         return nil
  #       end
  #       cloud['id']
  #     end
  #   }
  #   return cloud_ids
  # end

  # todo: some other common ones, accounts (tenants), etc.



  # a generic set of parse and find methods for any option source data
  def load_option_source_data(option_source, api_params={}, refresh=false, &block)
    @_option_source_cache ||= {}
    option_source_hash = "#{option_source}#{api_params.empty? ? '' : api_params.to_s}"
    data = @_option_source_cache[option_source_hash]
    if data.nil? || refresh
      json_response = options_interface.options_for_source(option_source, api_params)
      data = json_response['data'].collect {|it|
        {
          "name" => it["name"], 
          "value" => it["value"], 
          "id" => (it["id"] || it["value"]),
          "code" => it["code"]
        }
      }
      @_option_source_cache[option_source_hash] = data
    end
    return data
  end

  # todo: some other common ones, accounts (tenants), etc.
  # todo: a generic set of parse and find methods like 
  # like this:
  def parse_option_source_id_list(option_source, id_list, api_params={}, refresh=false)
    option_source_label = option_source.to_s # .capitalize
    option_data = load_option_source_data(option_source, api_params, refresh)
    found_ids = []
    parse_id_list(id_list).each {|record_id|
      lowercase_id = record_id.to_s.downcase
      # need to parameterize this behavior
      if record_id.to_s.empty?
        # never match blank nil or empty strings
        print_red_alert "#{option_source_label} cannot be not found by with a blank id!"
        return nil
      # elsif record_id.to_s =~ /\A\d{1,}\Z/
      #   # always allow any ID for now..
      #   found_ids << record_id
      else
        # search with in a presedence by value, then name, then id (usually same as value)
        # exact match on value first.
        matching_results = []
        matching_results = option_data.select {|it| it['value'] && it['value'] == record_id }
        # match on value case /i
        if matching_results.empty?
          matching_results = option_data.select {|it| it['value'] && it['value'].to_s.downcase == lowercase_id }
        end
        # match on name case /i
        if matching_results.empty?
          matching_results = option_data.select {|it| it['name'] && it['name'].to_s.downcase == lowercase_id } 
        end
        # match on id too, in case it is returned and different from value?
        if matching_results.empty?
          matching_results = option_data.select {|it| it['id'] && it['id'].to_s.downcase == lowercase_id } 
        end
        if matching_results.empty?
          print_red_alert "No #{option_source_label} found matching name or id '#{record_id}'"
          return nil
        elsif matching_results.size > 1
          print_red_alert "#{matching_results.size} #{option_source_label} found matching name '#{record_id}'. Try specifying the id instead."
          return nil
        else
          matching_result = matching_results[0]
          if matching_result['value']
            found_ids << matching_result['value']
          else
            found_ids << matching_result['id']
          end
        end
      end
    }
    return found_ids
  end

  def parse_cloud_id_list(id_list, api_params={}, refresh=false)
    parse_option_source_id_list('clouds', id_list, api_params, refresh)
  end

  def parse_group_id_list(id_list, api_params={}, refresh=false)
    parse_option_source_id_list('groups', id_list, api_params, refresh)
  end

  def parse_user_id_list(id_list, api_params={}, refresh=false)
    parse_option_source_id_list('users', id_list, api_params, refresh)
  end

  def parse_tenant_id_list(id_list, api_params={}, refresh=false)
    parse_option_source_id_list('allTenants', id_list, api_params, refresh)
  end

  # def parse_blueprints_id_list(id_list)
  #   parse_option_source_id_list('blueprints', id_list, api_params, refresh)
  # end

  def parse_project_id_list(id_list, api_params={}, refresh=false)
    parse_option_source_id_list('projects', id_list, api_params, refresh)
  end

end
