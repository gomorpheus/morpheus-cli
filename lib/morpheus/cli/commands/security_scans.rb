require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityScansCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

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
    opts.on('--security-package PACKAGE', String, "Filter by security package name or id") do |val|
      options[:security_package] ||= []
      options[:security_package] << val
    end
    opts.on('--server SERVER', String, "Filter by server name or id") do |val|
      options[:server] ||= []
      options[:server] << val
    end
    opts.on('--results', "Include the results object in the response under each security scan. This is a potentially very large object containing the raw results of the scan. Use with --json to see this data.") do
      params['results'] = true
    end
    super
  end

  def parse_list_options!(args, options, params)
    # parse --security-package
    # todo: one liner with find_by_name_or_id!
    if options[:security_package]
      params['securityPackageId'] = options[:security_package].collect do |val|
        record = find_by_name_or_id(:security_package, val)
        if record.nil?
          exit 1 #return 1, "Security Package not found by '#{val}'"
        else 
          record['id']
        end
      end
    end
    # parse --server
    if options[:server]
      params['serverId'] = options[:server].collect do |val|
        record = find_by_name_or_id(:server, val)
        if record.nil?
          exit 1 # return 1, "Server not found by '#{val}'"
        else
          record['id']
        end
      end
    end
    super
  end

  def build_get_options(opts, options, params)
    opts.on('--results', "Include the results object in the response under the security scan. This is a potentially very large object containing the raw results of the scan. Use with --json to see this data.") do
      params['results'] = true
    end
    super
  end

  def security_scan_list_column_definitions(options)
    {
      "ID" => 'id',
      "Security Package" => lambda {|it| it['securityPackage']['name'] rescue '' },
      "Type" => lambda {|it| it['securityPackage']['type']['name'] rescue '' },
      "Server" => lambda {|it| it['server']['name'] rescue '' },
      "Scan Date" => lambda {|it| format_local_dt(it['scanDate']) },
      "Status" => lambda {|it| it['status'] },
      "Score" => lambda {|it| it['scanScore'] },
      "Results" => lambda {|it| format_security_scan_results_summary(it) },

    }
  end

  def security_scan_column_definitions(options)
    {
      "ID" => 'id',
      "Security Package" => lambda {|it| it['securityPackage']['name'] rescue '' },
      "Type" => lambda {|it| it['securityPackage']['type']['name'] rescue '' },
      "Server" => lambda {|it| it['server']['name'] rescue '' },
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
