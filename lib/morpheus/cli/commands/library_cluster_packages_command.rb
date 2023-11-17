require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryClusterPackagesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-cluster-packages'

  register_subcommands :list, :get, :add, :update, :remove

  def initialize()
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_cluster_packages_interface = @api_client.library_cluster_packages
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List cluster packages."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @library_cluster_packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_packages_interface.dry.list(params)
        return
      end
      # do it
      json_response = @library_cluster_packages_interface.list(params)
      # print and/or return result
      # return 0 if options[:quiet]
      if options[:json]
        puts as_json(json_response, options, "clusterPackages")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['clusterPackages'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "clusterPackages")
        return 0
      end
      packages = json_response['clusterPackages']
      title = "Morpheus Library - Cluster Packages"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles
      if packages.empty?
        print cyan,"No cluster packages found.",reset,"\n"
      else
        rows = packages.collect do |package|
          {
              id: package['id'],
              name: package['name'],
              type: package['type'],
              packageType: package['packageType'],
              enabled: package['enabled']

          }
        end
        print as_pretty_table(rows, [:id, :name, :type, :packageType, :enabled], options)
        print_results_pagination(json_response, {})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[clusterPackage]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display cluster package details." + "\n" +
                    "[clusterPackage] is required. This is the id of a cluster package."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    id_list.each do |id|

    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    begin
      @library_cluster_packages_interface.setopts(options)

      if options[:dry_run]
          print_dry_run @library_cluster_packages_interface.dry.get(id)
        return
      end
      package = find_package_by_id(id)
      if package.nil?
        return 1
      end

      json_response = {'package' => package}

      if options[:json]
        puts as_json(json_response, options, "package")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "package")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['package']], options)
        return 0
      end

      print_h1 "Cluster Package Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Code" => lambda {|it| it['code']},
        "Enabled" => lambda {|it| format_boolean(it['enabled'])},
        "Description" => lambda {|it|it['description']},
        "Package Version" => lambda {|it| it['packageVersion']},
        "Package Type" => lambda {|it| it['packageType']},
        "Type" => lambda {|it| it['type'] },
        "Repeat Install" => lambda {|it| format_boolean(it['repeatInstall'])},
        "Logo" => lambda {|it| it['imagePath'] },
        "Dark Logo" => lambda {|it| it['darkImagePath'] },
        "Spec Templates" => lambda {|it| 
          "(#{it['specTemplates'].count}) #{it['specTemplates'].collect {|it| it['name'] }.join(', ')}"
        }
      }

      print_description_list(description_cols, package)

      if (package['optionTypes'] || []).count > 0
        rows = package['optionTypes'].collect do |opt|
          {
              label: opt['fieldLabel'],
              type: opt['type']
          }
        end
        print_h2 "Option Types"
        puts as_pretty_table(rows, [:label, :type])
      end

      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    logo_file = nil
    dark_logo_file = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('-n', '--name VALUE', String, "Name for this cluster package") do |val|
        params['name'] = val
      end
      opts.on('-d', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('-c', '--code VALUE', String, "Code") do |val|
        params['code'] = val
      end
      opts.on('-e', '--enabled [on|off]', String, "Can be used to enable / disable package. Default is on") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-r', '--repeatInstall [on|off]', String, "Can be used to retry install package if initial fails") do |val|
        params['repeatInstall'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-t', '--type VALUE', String, "Type") do |val|
        params['type'] = val
      end
      opts.on('-p', '--packageType VALUE', String, "Package Type") do |val|
        params['packageType'] = val
      end
      opts.on('-v', '--packageVersion VALUE', String, "Package Version") do |val|
        params['packageVersion'] = val
      end
      opts.on('--spec-templates [x,y,z]', Array, "List of Spec Templates to include in this package, comma separated list of IDs.") do |list|
        unless list.nil?
          params['specTemplates'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--logo FILE', String, "Upload a custom logo icon") do |val|
        filename = val
        logo_file = nil
        if filename == 'null'
          logo_file = 'null' # clear it
        else
          filename = File.expand_path(filename)
          if !File.exist?(filename)
            raise_command_error "File not found: #{filename}"
          end
          logo_file = File.new(filename, 'rb')
        end
      end
      opts.on('--dark-logo FILE', String, "Upload a custom dark logo icon") do |val|
        filename = val
        dark_logo_file = nil
        if filename == 'null'
          dark_logo_file = 'null' # clear it
        else
          filename = File.expand_path(filename)
          if !File.exist?(filename)
            raise_command_error "File not found: #{filename}"
          end
          dark_logo_file = File.new(filename, 'rb')
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a cluster package."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      params['name'] = args[0]
    end
    begin
      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # prompt for options
        if params['name'].nil?
          params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options], @api_client,{})['name']
        end

        # code
        if params['code'].nil?
          params['code'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'text', 'fieldLabel' => 'Code', 'required' => true}], options[:options], @api_client,{})['code']
        end

        # description
        if params['description'].nil?
          params['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false}], options[:options], @api_client,{})['description']
        end

        # enabled
        if params['enabled'].nil?
          params['enabled'] = Morpheus::Cli::OptionTypes.confirm("Enabled?", {:default => true}) == true
        end

        # enabled
        if params['repeatInstall'].nil?
          params['repeatInstall'] = Morpheus::Cli::OptionTypes.confirm("Repeat Install?", {:default => true}) == true
        end

        # type
        if params['type'].nil?
          params['type'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Type', 'required' => true, 'optionSource' => 'clusterPackageTypes'}], options[:options], @api_client,{})['type']
        end

        # packageType
        if params['packageType'].nil?
          params['packageType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'packageType', 'packageType' => 'text', 'fieldLabel' => 'Package Type', 'required' => true}], options[:options], @api_client,{})['packageType']
        end
        
        # packageVersion
        if params['packageVersion'].nil?
          params['packageVersion'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'packageVersion', 'packageVersion' => 'text', 'fieldLabel' => 'Package Version', 'required' => true}], options[:options], @api_client,{})['packageVersion']
        end

        # logo
        if params['iconPath'].nil?
          params['iconPath'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'iconPath', 'fieldLabel' => 'Logo', 'type' => 'select', 'optionSource' => 'iconList'}], options[:options], @api_client,{})['iconPath']
        end

        # specTemplates
        if params['specTemplates'].nil?
          spec_templates = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'specTemplates', 'fieldLabel' => 'Spec Templates', 'type' => 'multiSelect', 'required' => true, 'optionSource' => 'clusterResourceSpecTemplates'}], options[:options], @api_client, {})['specTemplates']

          params['specTemplates'] = spec_templates
        end
        payload = {'clusterPackage' => params}
      end

      @library_cluster_packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_packages_interface.dry.create(payload)
        return
      end

      json_response = @library_cluster_packages_interface.create(payload)
      if json_response['success']
        if logo_file || dark_logo_file
          begin
            @library_cluster_packages_interface.update_logo(json_response['id'], logo_file, dark_logo_file)
          rescue RestClient::Exception => e
            print_red_alert "Failed to save logo!"
            print_rest_exception(e, options)
          end
        end
      end

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Cluster Package #{params['name']}"
      get([json_response['id']])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    logo_file = nil
    dark_logo_file = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('-n', '--name VALUE', String, "Name for this cluster package") do |val|
        params['name'] = val
      end
      opts.on('-d', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('-c', '--code VALUE', String, "Code") do |val|
        params['code'] = val
      end
      opts.on('-e', '--enabled [on|off]', String, "Can be used to enable / disable package. Default is on") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-r', '--repeatInstall [on|off]', String, "Can be used to retry install package if initial fails") do |val|
        params['repeatInstall'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-t', '--type VALUE', String, "Type") do |val|
        params['type'] = val
      end
      opts.on('-p', '--packageType VALUE', String, "Package Type") do |val|
        params['packageType'] = val
      end
      opts.on('-v', '--packageVersion VALUE', String, "Package Version") do |val|
        params['packageVersion'] = val
      end
      opts.on('--spec-templates [x,y,z]', Array, "List of Spec Templates to include in this package, comma separated list of IDs.") do |list|
        unless list.nil?
          params['specTemplates'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--logo FILE', String, "Upload a custom logo icon") do |val|
        filename = val
        logo_file = nil
        if filename == 'null'
          logo_file = 'null' # clear it
        else
          filename = File.expand_path(filename)
          if !File.exist?(filename)
            raise_command_error "File not found: #{filename}"
          end
          logo_file = File.new(filename, 'rb')
        end
      end
      opts.on('--dark-logo FILE', String, "Upload a custom dark logo icon") do |val|
        filename = val
        dark_logo_file = nil
        if filename == 'null'
          dark_logo_file = 'null' # clear it
        else
          filename = File.expand_path(filename)
          if !File.exist?(filename)
            raise_command_error "File not found: #{filename}"
          end
          dark_logo_file = File.new(filename, 'rb')
        end
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a cluster package." + "\n" +
                    "[id] is required. This is the id of a cluster package."
    end

    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    begin
      cluster_package = find_package_by_id(args[0])
      exit 1 if cluster_package.nil?
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      end
     
      if params.empty? && !logo_file && !dark_logo_file
        print_green_success "Nothing to update"
        exit 1
      end
      payload = {'clusterPackage' => params}

      if options[:dry_run]
        print_dry_run @library_cluster_packages_interface.dry.update(cluster_package['id'], payload)
        return 0
      end

      if (logo_file || dark_logo_file) && params.empty?
        begin
          @library_cluster_packages_interface.update_logo(cluster_package['id'], logo_file, dark_logo_file)
          print_green_success "Updated Cluster Package #{params['name'] || cluster_package['name']}"
        rescue RestClient::Exception => e
          print_red_alert "Failed to save logo!"
          print_rest_exception(e, options)
        end
      else
        json_response = @library_cluster_packages_interface.update(cluster_package['id'], payload)
        if json_response['success']
          if logo_file || dark_logo_file
            begin
              @library_cluster_packages_interface.update_logo(json_response['id'], logo_file, dark_logo_file)
            rescue RestClient::Exception => e
              print_red_alert "Failed to save logo!"
              print_rest_exception(e, options)
            end
          end
        end
        if options[:json]
          print JSON.pretty_generate(json_response), "\n"
          return 0
        end
  
        print_green_success "Updated Cluster Package #{params['name'] || cluster_package['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[clusterPackage]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a cluster package." + "\n" +
                    "[clusterPackage] is required. This is the id of a cluster package."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      cluster_package = find_package_by_id(args[0])
      if cluster_package.nil?
        return 1
      end

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cluster package #{cluster_package['name']}?", options)
        exit
      end

      @library_cluster_packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_cluster_packages_interface.dry.destroy(cluster_package['id'])
        return
      end
      json_response = @library_cluster_packages_interface.destroy(cluster_package['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Removed Cluster Package #{cluster_package['name']}"
        else
          print_red_alert "Error removing cluster package: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private

  def find_package_by_id(id)
    begin
      json_response = @library_cluster_packages_interface.get(id.to_i)
      return json_response['clusterPackage']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Cluster package not found by id #{id}"
      else
        raise e
      end
    end
  end

  def print_packages_table(packages, opts={})
    columns = [
      {"ID" => lambda {|package| package['id'] } },
      {"NAME" => lambda {|package| package['name'] } },
      {"TECHNOLOGY" => lambda {|package| format_package_technology(package) } },
      {"DESCRIPTION" => lambda {|package| package['description'] } },
      {"OWNER" => lambda {|package| package['account'] ? package['account']['name'] : '' } }
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(packages, columns, opts)
  end
end