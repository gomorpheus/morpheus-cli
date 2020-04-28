require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for working with Operations.
# This includes the Dashboard, Activity, and more... (coming soon)
module Morpheus::Cli::OperationsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def format_activity_severity(severity, return_color=cyan)
    out = ""
    status_string = severity
    if status_string == 'critical'
      out << "#{red}#{status_string.capitalize}#{return_color}"
    elsif status_string == 'warning'
      out << "#{yellow}#{status_string.capitalize}#{return_color}"
    elsif status_string == 'info'
      out << "#{cyan}#{status_string.capitalize}#{return_color}"
    else
      out << "#{cyan}#{status_string}#{return_color}"
    end
    out
  end

  def format_activity_display_object(item)
    out = ""
    if item['name']
      out << item['name']
    end
    if item['objectType']
      out << " (#{item['objectType']} #{item['objectId']})"
    end
    if item['deleted']
      out << " [deleted]"
    end
    out
  end

end
