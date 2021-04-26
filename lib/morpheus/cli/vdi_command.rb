require 'morpheus/cli/cli_command'

# CLI command for the VDI (Persona)
class Morpheus::Cli::VdiCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::OptionSourceHelper

  # set_command_name :'desktops'
  set_command_name :'vdi'
  set_command_description "Virtual Desktop Persona: View and allocate your own virtual desktops"

  register_subcommands :list, :get, :allocate, :open

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @vdi_interface = @api_client.vdi
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = "List available virtual desktops (VDI pool)."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @vdi_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_interface.dry.list(params)
      return
    end
    json_response = @vdi_interface.list(params)
    vdi_pools = json_response[vdi_desktop_list_key]
    render_response(json_response, options, vdi_desktop_list_key) do
      print_h1 "Morpheus Virtual Desktops", parse_list_subtitles(options), options
      if vdi_pools.empty?
        print cyan,"No virtual desktops found.",reset,"\n"
      else
        list_columns = {
          # "ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name'] },
          "Status" => lambda {|it| format_virtual_desktop_status(it) },
        }
        #list_columns["Config"] = lambda {|it| truncate_string(it['config'], 100) }
        print as_pretty_table(vdi_pools, list_columns.upcase_keys!, options)
        print_results_pagination(json_response)

      end
      print reset,"\n"
    end
    return 0, nil
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific virtual desktop.
[name] is required. This is the name or id of a virtual desktop (VDI pool).
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    vdi_pool = nil
    if id.to_s !~ /\A\d{1,}\Z/
      vdi_pool = find_vdi_pool_by_name(id)
      return 1, "Virtual desktop not found for #{id}" if vdi_pool.nil?
      id = vdi_pool['id']
    end
    @vdi_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_interface.dry.get(id, params)
      return
    end
    json_response = @vdi_interface.get(id, params)
    vdi_pool = json_response[vdi_desktop_object_key]
    render_response(json_response, options, vdi_desktop_object_key) do
      print_h1 "Virtual Desktop Details", [], options
      print cyan
      show_columns = {
        #"ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Status" => lambda {|it| it['status'] },
        #"Allocation ID" => lambda {|it| it['allocation']['id'] rescue '' },
        # todo: more allocation info can be shown here perhaps...
      }
      #show_columns.delete("Allocation ID") unless vdi_pool['allocation'] && vdi_pool['allocation']['id']
      print as_description_list(vdi_pool, show_columns, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def allocate(args)
    options = {}
    params = {}
    payload = {}
    pool_id = nil
    
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[desktop] [options]")
      opts.on('--desktop DESKTOP', String, "Virtual Desktop Name or ID") do |val|
        pool_id = val.to_s
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Allocate a virtual desktop for use.
[desktop] is required, this is name or id of a virtual desktop (VDI Pool).
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0)
    connect(options)
    if args.count > 0
      pool_id = args.join(" ")
    end

    # prompt for Virtual Desktop (VDI Pool) to allocate
    vdi_pool = nil
    if pool_id
      vdi_pool = find_vdi_pool_by_name_or_id(pool_id)
      return [1, "Virtual Desktop not found"] if vdi_pool.nil?
      pool_id = vdi_pool['id']
    elsif
      vdi_pool_option_type = {'fieldName' => 'desktop', 'fieldLabel' => 'Virtual Desktop', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        # @options_interface.options_for_source("vdiPools", {})['data']
        @vdi_interface.list({max:10000})[vdi_desktop_list_key].collect {|it|
          {'name' => it['name'], 'value' => it['id']}
        } }, 'required' => true, 'description' => 'Virtual Desktop (VDI pool) name or id'}
      pool_id = Morpheus::Cli::OptionTypes.prompt([vdi_pool_option_type], options[:options], @api_client, options[:params])['desktop']
      vdi_pool = find_vdi_pool_by_name_or_id(pool_id.to_s)
      return [1, "Virtual Desktop not found"] if vdi_pool.nil?
      pool_id = vdi_pool['id']
    end

    payload = {}
    if options[:payload]
      payload = options[:payload]
    end
    payload.deep_merge!(parse_passed_options(options))
    
    @vdi_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_interface.dry.allocate(vdi_pool['id'], payload, params)
      return
    end
    json_response = @vdi_interface.allocate(vdi_pool['id'], payload, params)
    vdi_pool = json_response[vdi_desktop_object_key]
    render_response(json_response, options) do
      print_green_success "Allocated virtual desktop '#{vdi_pool['name']}'"
      #_get([vdi_pool['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end


  def open(args)
    options = {}
    params = {}
    payload = {}
    pool_id = nil
    
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[desktop] [options]")
      opts.on('--desktop DESKTOP', String, "Virtual Desktop Name or ID") do |val|
        pool_id = val.to_s
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Open a virtual desktop console in your web browser.
[desktop] is required, this is name or id of a virtual desktop (VDI Pool).
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0)
    connect(options)
    if args.count > 0
      pool_id = args.join(" ")
    end

    # prompt for Virtual Desktop (VDI Pool) to allocate
    vdi_pool = nil
    if pool_id
      vdi_pool = find_vdi_pool_by_name_or_id(pool_id)
      return [1, "Virtual Desktop not found"] if vdi_pool.nil?
      pool_id = vdi_pool['id']
    elsif
      vdi_pool_option_type = {'fieldName' => 'desktop', 'fieldLabel' => 'Virtual Desktop', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        # @options_interface.options_for_source("vdiPools", {})['data']
        @vdi_interface.list({max:10000})[vdi_desktop_list_key].collect {|it|
          {'name' => it['name'], 'value' => it['id']}
        } }, 'required' => true, 'description' => 'Virtual Desktop (VDI pool) name or id'}
      pool_id = Morpheus::Cli::OptionTypes.prompt([vdi_pool_option_type], options[:options], @api_client, options[:params])['desktop']
      vdi_pool = find_vdi_pool_by_name_or_id(pool_id.to_s)
      return [1, "Virtual Desktop not found"] if vdi_pool.nil?
      pool_id = vdi_pool['id']
    end

    # find allocation ID
    # if not found, prompt to allocate now before opening a link to the terminal URL
    allocation_id = nil
    if vdi_pool['allocation']
      allocation_id = vdi_pool['allocation']['id']
      # could check vdi_pool['allocation']['status']
    else
      puts cyan + "You are not currently allocated desktop '#{vdi_pool['name']}'" + reset
      # could check vdi_pool['status'] and error if not 'available'
      if !options[:no_prompt]
        if ::Morpheus::Cli::OptionTypes::confirm("Would you like to allocate this desktop for use now?", options.merge({default: true}))
          # allocate([vdi_pool['id']])
          json_response = @vdi_interface.allocate(vdi_pool['id'], {}, {})
          vdi_pool = json_response[vdi_desktop_object_key]
          allocation_id = vdi_pool['allocation']['id']
        end
      end
    end
    
    if allocation_id.nil?
      print_red_alert "You must first allocate virtual desktop '#{vdi_pool['name']}'"
      print_red_alert "Try `vdi allocate \"#{vdi_pool['name']}\"`"
      return 1, "No allocation"
    end

    link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/vdi/terminal/#{allocation_id}"

    if options[:dry_run]
      puts Morpheus::Util.open_url_command(link)
      return 0
    end
    return Morpheus::Util.open_url(link)

  end

  private

  def vdi_desktop_object_key
    # 'vdiPool'
    'desktop'
  end

  def vdi_desktop_list_key
    # 'vdiPools'
    'desktops'
  end

  def find_vdi_pool_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_vdi_pool_by_id(val)
    else
      return find_vdi_pool_by_name(val)
    end
  end

  # this returns optionTypes and list does not..
  def find_vdi_pool_by_id(id)
    begin
      json_response = @vdi_interface.get(id.to_i)
      return json_response[vdi_desktop_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Virtual Desktop not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_vdi_pool_by_name(name)
    json_response = @vdi_interface.list({name: name.to_s})
    vdi_pools = json_response[vdi_desktop_list_key]
    if vdi_pools.empty?
      print_red_alert "Virtual Desktop not found by name '#{name}'"
      return nil
    elsif vdi_pools.size > 1
      print_red_alert "#{vdi_pools.size} virtual desktops found by name '#{name}'"
      puts_error as_pretty_table(vdi_pools, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return vdi_pools[0]
    end
  end

  # def format_vdi_pool_status(vdi_pool, return_color=cyan)
  #   out = ""
  #   status_string = vdi_pool['status'].to_s.downcase
  #   if status_string
  #     if ['available'].include?(status_string)
  #       out << "#{green}#{status_string.upcase}"
  #     elsif ['unavailable'].include?(status_string)
  #       out << "#{red}#{status_string.upcase}"
  #     else
  #       out << "#{return_color}#{status_string.upcase}"
  #     end
  #   end
  #   out + return_color
  # end

  def format_virtual_desktop_status(vdi_pool, return_color=cyan)
    out = ""
    # status_string = vdi_pool['status'].to_s.downcase
    # status_string = ""
    # if vdi_pool['allocation']
    #   status_string = vdi_pool['allocation']['status'].to_s.downcase
    # else
    #   # show pool status eg. AVAILABLE or UNAVAILABLE
    #   status_string = vdi_pool['status'].to_s.downcase
    # end
    status_string = vdi_pool['allocationStatus'].to_s.downcase
    if vdi_pool['allocation'].nil?
      status_string = vdi_pool['status'].to_s.downcase
      # if status_string == 'available'
      #   status_string = 'unallocated'
      # end
    end

    if status_string
      if ['available', 'reserved'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      # elsif ['preparing'].include?(status_string)
      #   out << "#{yellow}#{status_string.upcase}"
      # elsif ['reserved', 'shutdown'].include?(status_string)
      #   out << "#{yellow}#{status_string.upcase}"
      elsif ['failed'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{return_color}#{status_string.upcase}"
      end
    end
    out + return_color
  end


end
