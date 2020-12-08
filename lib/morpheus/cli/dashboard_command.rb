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
        "Total Instances" => lambda {|it|
          it['instanceStats']['total'] rescue nil
        },
        "Running Instances" => lambda {|it|
          it['instanceStats']['running'] rescue nil
        },
        "Used Storage" => lambda {|it|
          ((it['instanceStats']['maxStorage'].to_i > 0) ? ((it['instanceStats']['usedStorage'].to_f / it['instanceStats']['maxStorage'].to_f) * 100).round(1) : 0).to_s + '%' rescue nil
        },
        "Monitoring" => lambda {|it|
          monitoring_status = nil
          begin
            n = it['monitoring']['openIncidents'] rescue nil
            if n.nil? 
              n = it['appStatus']['openIncidents'] rescue nil
            end
            if n == 1
              monitoring_status = "1 Open Incident"
            elsif n
              monitoring_status = "#{n} Open Incidents"
            end
          rescue
            
          end
          monitoring_status
        },
      }
      print as_description_list(json_response, status_column_definitions, options)
      # print reset,"\n"

      print_h2 "Last 7 Days Backups"
      backup_status_column_definitions = {
        "Total" => lambda {|it|
          it['backups']['accountStats']['lastSevenDays']['completed'] rescue nil
        },
        "Successful" => lambda {|it|
          it['backups']['accountStats']['lastSevenDays']['successful'] rescue nil
        },
        "Failed" => lambda {|it|
          it['backups']['accountStats']['lastSevenDays']['failed'] rescue nil
        },

      }
      #print as_description_list(json_response, backup_status_column_definitions, options)
      print as_pretty_table([json_response], backup_status_column_definitions, options)
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
