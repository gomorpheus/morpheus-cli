require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::DashboardCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  set_command_name :dashboard
  set_command_description "View Morpheus Dashboard"

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @dashboard_interface = @api_client.dashboard
  end

  def usage
    "Usage: morpheus #{command_name}"
  end

  def handle(args)
    show(args)
  end
  
  def show(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on('-a', '--details', "Display all details: more instance usage stats, etc" ) do
        options[:details] = true
      end
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
View Morpheus Dashboard.
This includes instance and backup counts, favorite instances, monitoring and recent activity.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    params = {}
    params.merge!(parse_list_options(options))
    @dashboard_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @dashboard_interface.dry.get(params)
      return
    end
    json_response = @dashboard_interface.get(params)
    render_response(json_response, options) do
      print_h1 "Morpheus Dashboard", [], options

      ## STATUS

      status_column_definitions = {
        "Instances" => lambda {|it|
          format_number(it['instanceStats']['total']) rescue nil
        },
        "Running" => lambda {|it|
          format_number(it['instanceStats']['running']) rescue nil
        },
        # "Used Storage" => lambda {|it|
        #   ((it['instanceStats']['maxStorage'].to_i > 0) ? ((it['instanceStats']['usedStorage'].to_f / it['instanceStats']['maxStorage'].to_f) * 100).round(1) : 0).to_s + '%' rescue nil
        # },
      }
      print as_description_list(json_response, status_column_definitions, options)
      # print reset,"\n"

      stats = json_response['instanceStats']
      if stats
        print_h2 "Instance Usage", options
        print_stats_usage(stats, {include: [:max_cpu, :avg_cpu, :memory, :storage]})
      end

      

      open_incident_count = json_response['monitoring']['openIncidents'] rescue (json_response['appStatus']['openIncidents'] rescue nil)
      
      avg_response_time = json_response['monitoring']['avgResponseTime'] rescue nil
      warning_apps = json_response['monitoring']['warningApps'] rescue 0
      warning_checks = json_response['monitoring']['warningChecks'] rescue 0
      fail_checks = json_response['monitoring']['failChecks'] rescue 0
      fail_apps = json_response['monitoring']['failApps'] rescue 0
      success_checks = json_response['monitoring']['successChecks'] rescue 0
      success_apps = json_response['monitoring']['successApps'] rescue 0
      monitoring_status_color = cyan
      if fail_checks > 0 || fail_apps > 0
        monitoring_status_color = red
      elsif warning_checks > 0 || warning_apps > 0
        monitoring_status_color = yellow
      end
      
      print_h2 "Monitoring"

      monitoring_column_definitions = {
        "Status" => lambda {|it|
          if fail_apps > 0 || fail_checks > 0
            check_summary = [fail_apps > 0 ? "#{fail_apps} Apps" : nil,fail_checks > 0 ? "#{fail_checks} Checks" : nil].compact.join(", ")
            red + "ERROR" + " (" + check_summary + ")" + cyan
          elsif warning_apps > 0 || warning_checks > 0
            check_summary = [warning_apps > 0 ? "#{warning_apps} Apps" : nil,warning_checks > 0 ? "#{warning_checks} Checks" : nil].compact.join(", ")
            red + "WARNING" + " (" + check_summary + ")" + cyan
          else
            cyan + "HEALTHY" + cyan
          end
        },
        # "Availability" => lambda {|it|
        #   # todo
        # },
        "Response Time" => lambda {|it|
          # format_number(avg_response_time).to_s + "ms"
          (avg_response_time.round).to_s + "ms"
        },
        "Open Incidents" => lambda {|it|
          monitoring_status_color = cyan
          # if fail_checks > 0 || fail_apps > 0
          #   monitoring_status_color = red
          # elsif warning_checks > 0 || warning_apps > 0
          #   monitoring_status_color = yellow
          # end
          if open_incident_count.nil? 
            yellow + "n/a" + cyan + "\n"
          elsif open_incident_count == 0
            monitoring_status_color + "0 Open Incidents" + cyan
          elsif open_incident_count == 1
            monitoring_status_color + "1 Open Incident" + cyan
          else
            monitoring_status_color + "#{open_incident_count} Open Incidents" + cyan
          end
        }
      }
      #print as_description_list(json_response, monitoring_column_definitions, options)
      print as_pretty_table([json_response], monitoring_column_definitions.upcase_keys!, options)

      
      if json_response['logStats']
        # todo: should come from monitoring.startMs-endMs
        log_period_display = "7 Days"
        print_h2 "Logs (#{log_period_display})", options
        error_log_data = json_response['logStats']['data'].find {|it| it['key'].to_s.upcase == 'ERROR' }
        error_count = error_log_data["count"] rescue 0
        fatal_log_data = json_response['logStats']['data'].find {|it| it['key'].to_s.upcase == 'FATAL' }
        fatal_count = fatal_log_data["count"] rescue 0
        # total error is actaully error + fatal
        total_error_count = error_count + fatal_count
        # if total_error_count.nil? 
        #   print yellow + "n/a" + cyan + "\n"
        # elsif total_error_count == 0
        #   print cyan + "0 Errors" + cyan + "\n"
        # elsif total_error_count == 1
        #   print red + "1 Error" + cyan + "\n"
        # else
        #   print red + "#{total_error_count} Errors" + cyan + "\n"
        # end
        if total_error_count == 0
          print cyan + "(0 Errors)" + cyan + "\n"
          #print cyan + "0-0-0-0-0-0-0-0 (0 Errors)" + cyan + "\n"
        end
        if error_count > 0
          if error_log_data["values"]
            log_plot = ""
            plot_index = 0
            error_log_data["values"].each do |k, v|
              if v.to_i == 0
                log_plot << cyan + v.to_s
              else
                log_plot << red + v.to_s
              end
              if plot_index != error_log_data["values"].size - 1
                log_plot << cyan + "-"
              end
              plot_index +=1
            end
            print log_plot
            print " "
            if error_count == 0
              print cyan + "(0 Errors)" + cyan
            elsif error_count == 1
              print red + "(1 Errors)" + cyan
            else
              print red + "(#{error_count} Errors)" + cyan
            end
            print reset + "\n"
          end
        end
        if fatal_count > 0
          if fatal_log_data["values"]
            log_plot = ""
            plot_index = 0
            fatal_log_data["values"].each do |k, v|
              if v.to_i == 0
                log_plot << cyan + v.to_s
              else
                log_plot << red + v.to_s
              end
              if plot_index != fatal_log_data["values"].size - 1
                log_plot << cyan + "-"
              end
              plot_index +=1
            end
            print log_plot
            print " "
            if fatal_count == 0
              print cyan + "(0 FATAL)" + cyan
            elsif fatal_count == 1
              print red + "(1 FATAL)" + cyan
            else
              print red + "(#{fatal_count} FATAL)" + cyan
            end
            print reset + "\n"
          end
        end
      end

      print_h2 "Backups (7 Days)"
      backup_status_column_definitions = {
        # "Total" => lambda {|it|
        #   it['backups']['accountStats']['lastSevenDays']['completed'] rescue nil
        # },
        "Successful" => lambda {|it|
          it['backups']['accountStats']['lastSevenDays']['successful'] rescue nil
        },
        "Failed" => lambda {|it|
          n = it['backups']['accountStats']['lastSevenDays']['failed'] rescue nil
          if n == 0
            cyan + n.to_s + reset
          else
            red + n.to_s + reset
          end
        }
      }
      print as_description_list(json_response, backup_status_column_definitions, options)
      #print as_pretty_table([json_response], backup_status_column_definitions, options)
      # print reset,"\n"

      favorite_instances = json_response["provisioning"]["favoriteInstances"] || [] rescue []
      if favorite_instances.empty?
        # print cyan, "No favorite instances.",reset,"\n"
      else
        print_h2 "My Instances"
        favorite_instances_columns = {
          "ID" => lambda {|instance|
            instance['id']
          },
          "Name" => lambda {|instance|
            instance['name']
          },
          "Type" => lambda {|instance|
            instance['instanceType']['name'] rescue nil
          },
          "IP/PORT" => lambda {|instance|
            format_instance_connection_string(instance)
          },
          "Status" => lambda {|it| format_instance_status(it) }
        }
        #print as_description_list(json_response, status_column_definitions, options)
        print as_pretty_table(favorite_instances, favorite_instances_columns, options)
        # print reset,"\n"
      end

      # RECENT ACTIVITY
      activity = json_response["activity"] || json_response["recentActivity"] || []
      print_h2 "Recent Activity", [], options
      if activity.empty?
        print cyan, "No activity found.",reset,"\n"
      else
        columns = [
          # {"SEVERITY" => lambda {|record| format_activity_severity(record['severity']) } },
          {"TYPE" => lambda {|record| record['activityType'] } },
          {"NAME" => lambda {|record| record['name'] } },
          {"RESOURCE" => lambda {|record| "#{record['objectType']} #{record['objectId']}" } },
          {"MESSAGE" => lambda {|record| record['message'] || '' } },
          {"USER" => lambda {|record| record['user'] ? record['user']['username'] : record['userName'] } },
          #{"DATE" => lambda {|record| "#{format_duration_ago(record['ts'] || record['timestamp'])}" } },
          {"DATE" => lambda {|record| 
            # show full time if searching for custom timerange, otherwise the default is to show relative time
            if params['start'] || params['end'] || params['timeframe']
              "#{format_local_dt(record['ts'] || record['timestamp'])}"
            else
              "#{format_duration_ago(record['ts'] || record['timestamp'])}"
            end

          } },
        ]
        print as_pretty_table(activity, columns, options)
        # print_results_pagination(json_response)
        # print reset,"\n"

      end

    end
    print reset,"\n"
    return 0, nil
  end


end
