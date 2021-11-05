require 'morpheus/cli/cli_command'

class Morpheus::Cli::SearchCommand
  include Morpheus::Cli::CliCommand
  
  set_command_name :search
  set_command_description "Global search for finding all types of objects"

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @search_interface = @api_client.search
  end

  def handle(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} #{command_name} [phrase]"
      opts.on("-g", "--go", "Go get details for the top search result instead of printing the list.") do
        options[:go] = true
      end
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
Global search for finding all types of objects
[phrase] is required. This is the phrase to search for.
Prints the list of search results with the most relevant first.
or use the --go option to get details about the top result instead.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, min:1)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    if options[:phrase].to_s.empty?
      raise_command_error "[phrase] is required.", args, optparse
    end
    params.merge!(parse_list_options(options))
    @search_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @search_interface.dry.list(params)
      return
    end
    json_response = @search_interface.list(params)
    search_results = json_response["hits"] || json_response["results"] || []
    top_result = search_results[0]
    if options[:go]
      if top_result
        print cyan,"Loading top search result: #{format_morpheus_type(top_result['type'])} #{top_result['name'] || top_result['id']} (score: #{top_result['score']})",reset,"\n"
        return go_to_search_result(top_result, options)
      else
        # print cyan,"No results found.",reset,"\n"
        raise_command_error "No search results for phrase '#{options[:phrase]}'"
      end
    end
    render_response(json_response, options, "hits") do
      print_h1 "Morpheus Search", parse_list_subtitles(options), options
      if search_results.empty?
        print cyan,"No results found.",reset,"\n"
      else
        columns = {
          "Type" => lambda {|it| format_morpheus_type(it['type']) },
          "ID" => 'id',
          # "UUID" => 'uuid',
          "Name" => 'name',
          "Decription" => 'description',
          #"Score" => 'score',
          "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        }
        print as_pretty_table(search_results, columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if search_results.empty?
      return 1, "no results found"
    else
      return 0, nil
    end
  end

  protected

  def format_morpheus_type(val)
    if val == "ComputeSite"
      "Group"
    elsif val == "ComputeZone"
      "Cloud"
    elsif val == "ComputeServer"
      "Host"
    elsif val == "ComputeServerGroup"
      "Cluster"
    elsif val == "ComputeZonePool"
      "Pool"
    else
      val
    end
  end
  
  def go_to_search_result(result, options)
    result_type = result['type']
    cmd_class = lookup_morpheus_command(result['type'])
    if cmd_class
      get_options = []
      get_options += (options[:remote] ? ["-r",options[:remote]] : [])
      get_options += (options[:json] ? ["--json"] : [])
      get_options += (options[:yaml] ? ["--yaml"] : [])
      return cmd_class.new.handle(["get", result['id']] + get_options)
    else
      raise_command_error "Sorry, result cannot be loaded. type: #{result_type}, id: #{result['id']}, name: #{result['name']}"
    end
  end


  def lookup_morpheus_command(result_type)
    case result_type.to_s.downcase
    when "computezone","cloud","zone"
      Morpheus::Cli::Clouds
    when "computesite","group"
      Morpheus::Cli::Groups
    when "computeserver","server","host"
      Morpheus::Cli::Hosts
    when "computeservergroup","serverGroup","cluster"
      Morpheus::Cli::Clusters
    when "instance"
      Morpheus::Cli::Instances
    when "app"
      Morpheus::Cli::Apps
    when "container"
      Morpheus::Cli::Containers
    when "computezonefolder","zonefolder","resourcefolder"
      # crap, need result.zoneId, or resource-folders should not require cloud actually, get by id
      # Morpheus::Cli::CloudFoldersCommand
      nil
    when "computezonepool","zonepool","resourcepool"
      # crap, need result.zoneId, or resource-pools should not require cloud actually, get by id
      # Morpheus::Cli::CloudResourcePoolsCommand
      nil
    # when "chassis"
    #   Morpheus::Cli::ChassisCommand
    when "network"
      Morpheus::Cli::NetworksCommand
    when "networkgroup"
      Morpheus::Cli::NetworkGroupsCommand
    when "networkpool"
      Morpheus::Cli::NetworkPoolsCommand
    when "networkdomain"
      Morpheus::Cli::NetworkDomainsCommand
    when "virtualimage"
      Morpheus::Cli::VirtualImages
    when "loadbalancer"
      Morpheus::Cli::LoadBalancers
    # when "virtualserver","loadbalancerinstance"
    #   Morpheus::Cli::LoadBalancerInstances
    when "instancetype"
      # Morpheus::Cli::LibraryInstanceTypesCommand
      Morpheus::Cli::LibraryInstanceTypes
    when "instancetypelayout","layout"
      Morpheus::Cli::LibraryLayoutsCommand
    when "certificate"
      # todo: WHAT! didnt I write certs already!?
      Morpheus::Cli::CertificatesCommand
    when "keypair"
      Morpheus::Cli::KeyPairs
    when "integration"
      Morpheus::Cli::IntegrationsCommand
    when "account","tenant"
      Morpheus::Cli::TenantsCommand
    when "user"
      Morpheus::Cli::Users
    when "role"
      Morpheus::Cli::Roles
    when "wikipage","wiki"
      Morpheus::Cli::WikiCommand
    else
      nil
    end
  end

end

