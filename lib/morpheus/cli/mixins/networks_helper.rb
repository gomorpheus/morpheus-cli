require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for networking commands
module Morpheus::Cli::NetworksHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def network_servers_interface
    # @api_client.network_servers
    raise "#{self.class} has not defined @network_servers_interface" if @network_servers_interface.nil?
    @network_servers_interface
  end

  def find_network_server(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_server_by_id(val)
    else
      if server = find_network_server_by_name(val)
        return find_network_server_by_id(server['id'])
      end
    end
  end

  def find_network_server_by_id(id)
    begin
      # Use query parameter `details=true` to get the full type object with all its configuration settings and optionTypes
      json_response = @network_servers_interface.get(id.to_i, {details:true})
      return json_response['networkServer']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Server not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_server_by_name(name)
    # Use query parameter `details=true` to get the full type object with all its configuration settings and optionTypes
    json_response = @network_servers_interface.list({phrase: name.to_s, details:true})
    servers = json_response['networkServers']
    if servers.empty?
      print_red_alert "Network Server not found by name #{name}"
      return nil
    elsif servers.size > 1
      print_red_alert "#{servers.size} network servers found by name #{name}"
      rows = servers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return servers[0]
    end
  end

end
