require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityScansCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::ProvisioningHelper

  set_command_name :'security-scans'
  set_command_description "View and manage security scans."
  register_subcommands :list, :get, :remove

  # RestCommand settings
  register_interfaces :security_scans, 
                      :security_packages, :servers

  # display argument as [id] since name is not supported
  set_rest_has_name false
  set_rest_arg "id"

  protected

  def build_list_options(opts, options, params)
    opts.on('--server SERVER', String, "Filter by server name or id") do |val|
      options[:server] ||= []
      options[:server] << val
    end
    opts.on('--security-package PACKAGE', String, "Filter by security package name or id") do |val|
      options[:security_package] ||= []
      options[:security_package] << val
    end
    super
  end

  def parse_list_options!(args, options, params)
    if options[:server]
      params['serverId'] = options[:server].collect do |val|
        if val.to_s =~ /\A\d{1,}\Z/
          val.to_i
        else
          server = find_server_by_name(val)
          server['id']
        end
      end
    end
    if options[:security_package]
      params['securityPackageId'] = options[:security_package].collect do |val|
        if val.to_s =~ /\A\d{1,}\Z/
          val.to_i
        else
          records = @security_packages_interface.list({name: val.to_s})['securityPackages']
          if records.empty?
            print_red_alert "Security Package not found by name #{val}"
            exit 1
          elsif records.size > 1
            print_red_alert "#{records.size} security packages found by name #{val}"
            as_pretty_table(records, [:id, :name], {color: red})
            print_red_alert "Try using ID instead"
            print reset,"\n"
            exit 1
          else
            records[0]['id']
          end
        end
      end
    end
    super
  end

  def security_scan_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['securityPackage']['name'] rescue '' },
      "Type" => lambda {|it| it['securityPackage']['type']['name'] rescue '' },
      "Scan Date" => lambda {|it| format_local_dt(it['scanDate']) },
      "Status" => lambda {|it| it['status'] },
      "Score" => lambda {|it| it['scanScore'] },
      "Results" => lambda {|it| format_security_scan_results_summary(it) },

    }
  end

  def security_scan_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['securityPackage']['name'] rescue '' },
      "Type" => lambda {|it| it['securityPackage']['type']['name'] rescue '' },
      "Scan Date" => lambda {|it| format_local_dt(it['scanDate']) },
      "Status" => lambda {|it| it['status'] },
      "Score" => lambda {|it| it['scanScore'] },
      "Results" => lambda {|it| format_security_scan_results_summary(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def format_security_scan_results_summary(security_scan)
    totals = []
    totals << "Run: #{security_scan['runCount']}" # if security_scan['runCount'].to_i > 0
    totals << "Pass: #{security_scan['passCount']}" if security_scan['passCount'].to_i > 0
    totals << "Fail: #{security_scan['failCount']}" if security_scan['failCount'].to_i > 0
    totals << "Warn: #{security_scan['runCount']}" if security_scan['otherCount'].to_i > 0
    totals.join(", ")
  end
end
