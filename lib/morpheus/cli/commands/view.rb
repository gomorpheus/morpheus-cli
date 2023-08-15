require 'morpheus/cli/cli_command'
# require 'morpheus/routes'

class Morpheus::Cli::View
  include Morpheus::Cli::CliCommand

  set_command_description "Open the remote appliance in a web browser"
  set_command_name :'view'

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
  end
  
  def handle(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[path] [id]")
      # debate: should login using /login/ouath-redirect
      opts.on('-l', '--login', "Login with the CLI access token before loading the path." ) do
        options[:login] = true
      end
      opts.on('-L', '--old-login', "Alias for -l, --login" ) do
        options[:login] = true
      end
      opts.add_hidden_option('-L, --old-login')
      opts.on('--absolute', "Absolute path, do not search for a matching route to use") do
        options[:absolute_path] = true
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = <<-EOT
View the remote appliance in a web browser.
[path] is optional. This the path or resource type to load. The default is the index page "/".
[id] is optional. This is the resource name or id to be append to the path to load details of a specific object.
The [path] is matched against the #{prog_name} UI site map to find the best matching route.
Route matching is skipped if the path begins with a "/" or --absolute is used.
By default no authentication is done and the existing web browser session used.
The --login option will authenticate via the CLI access token and create a new browser session.

Examples:
    view --login
    view monitoring
    view user 1
    view user administrator
    view /infrastructure/clouds/2
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min: 0, max: 2)
    connect(options)
    # todo: it would actually be cool to use the params and include them on the path..
    # params.merge!(parse_query_options(options))
    # input, *ids = args
    input = args[0]
    id = args[1]
    # default to index page "/"
    path = input || "/"
    if options[:absolute_path] != true
      if path.start_with?("/")
        # treat like absolute path, no lookup
      else
        # lookup best matching route from sitemap
        # lookup plural routes first, so 'app' finds apps and not approvals
        found_route = Morpheus::Routes.lookup(path, id)
        if found_route
          # Morpheus::Logging::DarkPrinter.puts "Found matching route: '#{path}' => '#{found_route}'" if Morpheus::Logging.debug?
          path = found_route
        else
          # just use specified path
        end
      end
      # always add a leading slash
      path = path.start_with?("/") ? path : "/#{path}"
      # append id to path if passed
      if id
        # convert name to id
        # assume the last part of path is the type and use generic finder
        # only lookup names, and allow any id
        if id.to_s !~ /\A\d{1,}\Z/
          # record type is just args[0]
          record_type = input
          # assume the last part of path is the type
          # record_type = path.split("/").last
          # record_type.sub!('#!', '')
          record = find_by_name(record_type, id)
          if record.nil?
            raise_command_error("[id] is invalid. No #{record_type} found for '#{id}'", args, optparse)
          end
          id = record['id'].to_s
        end
        path = "#{path}/#{id}"
      end
    end
    # build the link to use, either our path or oauth-redirect to that path
    link = "#{@appliance_url}#{path}"
    if options[:login]
      # uh, this should need CGI::escape(path)
      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=#{path}"
    end
    if options[:dry_run]
      print_system_command_dry_run(Morpheus::Util.open_url_command(link), options)
      return 0, nil
    end
    return Morpheus::Util.open_url(link)
  end

end
