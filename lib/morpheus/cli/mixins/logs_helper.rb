require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for fetching log records.
# The including class must establish @logs_interface, @containers_interface, @servers_interface
module Morpheus::Cli::LogsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def logs_interface
    # @api_client.logs
    raise "#{self.class} has not defined @logs_interface" if @logs_interface.nil?
    @logs_interface
  end

  def containers_interface
    ## @api_client.containers
    raise "#{self.class} has not defined @logs_interface" if @containers_interface.nil?
    @containers_interface
  end

  def servers_interface
    # @api_client.servers
    raise "#{self.class} has not defined @servers_interface" if @servers_interface.nil?
    @servers_interface
  end

  def clusters_interface
    # @api_client.clusters
    raise "#{self.class} has not defined @clusters_interface" if @clusters_interface.nil?
    @clusters_interface
  end

  def print_log_records(log_records, options={})
    print format_log_records(log_records, options)
  end
  
  def format_log_records(log_records, options={})
    out = ""
    table_color = options.key?(:color) ? options[:color] : cyan
    log_records.each do |log_entry|
      log_level = ''
      case log_entry['level']
      when 'INFO'
        log_level = "#{blue}#{bold}INFO#{reset}"
      when 'DEBUG'
        log_level = "#{white}#{bold}DEBUG#{reset}"
      when 'WARN'
        log_level = "#{yellow}#{bold}WARN#{reset}"
      when 'ERROR'
        log_level = "#{red}#{bold}ERROR#{reset}"
      when 'FATAL'
        log_level = "#{red}#{bold}FATAL#{reset}"
      end
      out << table_color if table_color
      out << "[#{log_entry['ts']}] #{log_level} - #{log_entry['message'].to_s.strip}"
      out << table_color if table_color
      out << "\n"
    end
    return out
  end

end
