require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for working with remotes
module Morpheus::Cli::RemoteHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def format_appliance_name(appliance)
    app_name = appliance[:name]
    if app_name == 'remote-url'
      "(remote-url)"
    else
      app_name
    end
  end

  def format_appliance_slug(appliance)
    "[#{format_appliance_name(appliance)}] #{appliance[:url]}"
  end

  def format_appliance_status(appliance, return_color=cyan, show_current=false)
    return "" if !appliance
    status_str = appliance[:status] || appliance['status'] || "unknown" # get_object_value(appliance, :status)
    status_str = status_str.to_s # Symbols getting in here?
    status_str = status_str.empty? ? "unknown" : status_str.to_s.downcase
    status_str = status_str.gsub("-", " ") # change "http-error" to "http error"
    out = ""
    status_color = format_appliance_status_color(appliance)
    out << "#{status_color}#{status_str.upcase}#{return_color}"
    # meh, probably keep this separate
    if show_current && appliance[:active]
      out << " " + format_is_current() + return_color
    end
    out
  end

  def format_appliance_status_color(appliance)
    status = appliance[:status].to_s.downcase
    if status == 'ready'
      green
    elsif status == 'fresh'
      magenta
    elsif status == 'new'
      cyan
    elsif ['error', 'http-error', 'net-error', 'ssl-error', 'http-timeout', 'unreachable', 'unrecognized'].include?(status)
      red
    else
      yellow
    end
  end

  def format_is_current(return_color=cyan)
    "#{cyan}#{bold}(current)#{reset}#{return_color}"
  end

  def format_appliance_secure(app_map, return_color=cyan)
    return "" if !app_map
    out = ""
    app_url = (app_map[:url] || app_map[:host]).to_s
    is_ssl = app_url =~ /^https/
    if !is_ssl
      # out << "No (no SSL)"
      out << "No"
    else
      if app_map[:insecure]
        # out << "No (Ignore SSL Errors)"
        out << "No"
      else
        # should have a flag that gets set when everything actually looks good..
        out << "Yes"
      end
    end
    out
  end

  # get display info about the current and past sessions
  # 
  def get_appliance_session_blurbs(app_map)
    # app_map = OStruct.new(app_map)
    blurbs = []
    # Current User
    # 
    username = app_map[:username]
    
    # if app_map[:active]
    #   blurbs << "(current)"
    # end
    if app_map[:status] == 'ready'

      if app_map[:authenticated]
        #blurbs << app_map[:username] ? "Authenticated as #{app_map[:username]}" : "Authenticated"
        # blurbs << "Authenticated."
        if app_map[:last_login_at]
          blurbs << "Logged in #{format_duration_ago(app_map[:last_login_at])}"
        end
      else
        if app_map[:last_logout_at]
          blurbs << "Logged out #{format_duration_ago(app_map[:last_logout_at])}"
        else
          #blurbs << "Logged out"
        end
        if app_map[:last_login_at]
          blurbs << "Last login #{format_duration_ago(app_map[:last_login_at])}"
        end
      end

      if app_map[:last_success_at]
        blurbs << "Last success #{format_duration_ago(app_map[:last_success_at])}"
      end

    else
      
      if app_map[:last_check]
        if app_map[:last_check][:timestamp]
          blurbs << "Last checked #{format_duration_ago(app_map[:last_check][:timestamp])}"
        end
        if app_map[:last_check][:error]
          last_error_msg = truncate_string(app_map[:last_check][:error], 250)
          blurbs << "Error: #{last_error_msg}"
        end
        if app_map[:last_check][:http_status]
          blurbs << "HTTP #{app_map[:last_check][:http_status]}"
        end
      end

      if app_map[:last_success_at]
        blurbs << "Last Success: #{format_duration_ago(app_map[:last_success_at])}"
      end

    end

    return blurbs
  end


end
