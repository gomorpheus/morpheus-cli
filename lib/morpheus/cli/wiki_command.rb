require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::WikiCommand
  include Morpheus::Cli::CliCommand
  set_command_name :wiki
  register_subcommands :list, :get, :view, :add, :update, :remove, :'categories'

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @wiki_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).wiki
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--category VALUE', String, "Category") do |val|
        params['category'] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @wiki_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @wiki_interface.dry.list(params)
        return 0
      end
      json_response = @wiki_interface.list(params)
      render_result = render_with_format(json_response, options, 'pages')
      return 0 if render_result
      pages = json_response['pages']
      unless options[:quiet]
        title = "Morpheus Wiki Pages"
        subtitles = []
        if params['category']
          subtitles << "Category: #{params['category']}"
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if pages.empty?
          print cyan,"No wiki pages found.",reset,"\n"
        else
          columns = [
            {"ID" => lambda {|page| page['id'] } },
            {"NAME" => lambda {|page| page['name'] } },
            {"CATEGORY" => lambda {|page| page['category'] } },
            {"AUTHOR" => lambda {|page| page['updatedBy'] ? page['updatedBy']['username'] : '' } },
            {"CREATED" => lambda {|page| format_local_dt(page['dateCreated']) } },
            {"UPDATED" => lambda {|page| format_local_dt(page['lastUpdated']) } },
          ]
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print as_pretty_table(pages, columns, options)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--view', '--view', "View wiki page in web browser too.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      @wiki_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @wiki_interface.dry.get(args[0])
        else
          print_dry_run @wiki_interface.dry.list({name: args[0].to_s})
        end
        return 0
      end
      page = find_wiki_page_by_name_or_id(args[0])
      return 1 if page.nil?
      json_response = {'page' => page}
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      unless options[:quiet]
        print_h1 "Wiki Page Details"
        print cyan
        wiki_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Category" => 'category',
          # "Ref Type" => 'refType',
          # "Ref ID" => 'refId',
          "Reference" => lambda {|it| it['refType'] ? "#{it['refType']} (#{it['refId']})" : '' },
          #"Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
          "Updated By" => lambda {|it| it['updatedBy'] ? it['updatedBy']['username'] : '' }
        }
        if page['refType'].nil?
          wiki_columns.delete("Reference")
        end
        print_description_list(wiki_columns, page)
        print reset,"\n"

        print_h2 "Page Content"
        print cyan, page['content'], reset, "\n"

      end
      print reset,"\n"
      if open_wiki_link
        return view([page['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View a wiki page in a web browser" + "\n" +
                    "[id] is required. This is name or id of the wiki page."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      page = find_wiki_page_by_name_or_id(args[0])
      return 1 if page.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/operations/wiki/#{page['urlName']}"

      open_command = nil
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        open_command = "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        open_command = "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        open_command = "xdg-open #{link}"
      end

      if options[:dry_run]
        puts "system: #{open_command}"
        return 0
      end

      system(open_command)
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_wiki_page_option_types)
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options] ||= {}
      options[:options]['name'] ||= args[0]
    end
    connect(options)
    begin
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'page' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
        # prompt for options
        params = Morpheus::Cli::OptionTypes.prompt(add_wiki_page_option_types, options[:options], @api_client, options[:params])
        payload.deep_merge!({'page' => params}) unless params.empty?
      end

      @wiki_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @wiki_interface.dry.create(payload)
        return
      end
      json_response = @wiki_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['page']  ? json_response['page']['name'] : ''
        print_green_success "Wiki page #{display_name} added"
        get([json_response['page']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_wiki_page_option_types)
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin

      page = find_wiki_page_by_name_or_id(args[0])
      return 1 if page.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'page' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_wiki_page_option_types, options[:options], @api_client, options[:params])
        params = passed_options

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
        if params["category"] && (params["category"].strip == "" || params["category"].strip == "null")
          params["category"] = ""
        end
        payload.deep_merge!({'page' => params}) unless params.empty?
      end
      @wiki_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @wiki_interface.dry.update(page['id'], payload)
        return
      end
      json_response = @wiki_interface.update(page['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['page'] ? json_response['page']['name'] : ''
        print_green_success "Wiki page #{display_name} updated"
        get([json_response['page']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      page = find_wiki_page_by_name_or_id(args[0])
      return 1 if page.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the page #{page['name']}?")
        return 9, "aborted command"
      end
      @wiki_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @wiki_interface.dry.destroy(page['id'])
        return
      end
      json_response = @wiki_interface.destroy(page['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Wiki page #{page['name']} removed"
        # list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def categories(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @wiki_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @wiki_interface.dry.categories(params)
        return 0
      end
      json_response = @wiki_interface.categories(params)
      render_result = render_with_format(json_response, options, 'categories')
      return 0 if render_result
      categories = json_response['categories']
      unless options[:quiet]
        title = "Morpheus Wiki Categories"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if categories.empty?
          print cyan,"No wiki categories found.",reset,"\n"
        else
          columns = [
            {"CATEGORY" => lambda {|page| page['name'] } },
            {"# PAGES" => lambda {|it| it['pageCount'] } }
          ]
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print as_pretty_table(categories, columns, options)
          #print_results_pagination(json_response)
        end
        print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private
  def find_wiki_page_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_wiki_page_by_id(val)
    else
      return find_wiki_page_by_name(val)
    end
  end

  def find_wiki_page_by_id(id)
    raise "#{self.class} has not defined @wiki_interface" if @wiki_interface.nil?
    begin
      json_response = @wiki_interface.get(id)
      return json_response['page']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Wiki page not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_wiki_page_by_name(name)
    raise "#{self.class} has not defined @wiki_interface" if @wiki_interface.nil?
    pages = @wiki_interface.list({name: name.to_s})['pages']
    if pages.empty?
      print_red_alert "Wiki page not found by name #{name}"
      return nil
    elsif pages.size > 1
      print_red_alert "#{pages.size} wiki pages found by name #{name}"
      print as_pretty_table(pages, [:id,:name], {color:red})
      print reset,"\n"
      return nil
    else
      return pages[0]
    end
  end

  def add_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => true, 'displayOrder' => 3}
    ]
  end

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
      {'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3}
    ]
  end

end
