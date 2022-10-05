require 'morpheus/cli/cli_command'

class Morpheus::Cli::CurlCommand
  include Morpheus::Cli::CliCommand
  set_command_name :curl

  def handle(args)
    curl_method = nil
    curl_data = nil
    show_progress = false
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus curl [path]"
      opts.on( '-p', '--pretty', "Print result as parsed JSON. Alias for -j" ) do
        options[:json] = true
      end
      opts.on( '-X', '--request METHOD', "HTTP request method. Default is GET" ) do |val|
        curl_method = val
      end
      opts.on( '--post', "Set the HTTP request method to POST" ) do
        curl_method = "POST"
      end
      opts.on( '--put', "Set the HTTP request method to PUT" ) do
        curl_method = "POST"
      end
      opts.on( '--delete', "Set the HTTP request method to DELETE" ) do
        curl_method = "DELETE"
      end
      opts.on( '--data DATA', String, "HTTP request body for use with POST and PUT, typically JSON." ) do |val|
        curl_data = val
      end
      build_standard_api_options(opts, options)
      opts.footer = <<-EOT
This provides a way to execute arbitrary HTTP requests against the remote appliance.
By default the request includes the current remote URL and authorization header -H "Authorization: Bearer access_token"
Example: morpheus curl "/api/whoami"
EOT
    end

    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 1)
    
    # establish api client with connection, skips verification so check for appliance is done afterwards
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true, :skip_login => true}))
    if !@appliance_name
      raise_command_error "#{command_name} requires a remote to be specified, use -r [remote] or set the active remote with `remote use`"
    end

    # determine curl url, base_url is automatically applied
    api_path = args[0].to_s.strip

    # build query parameters from --query k=v
    query_params = parse_query_options(options)

    # build payload from --payload '{}' and --option k=v
    payload = parse_payload(options)

    request_opts = {}
    request_opts[:method] = curl_method ? curl_method.to_s.downcase.to_sym : :get
    request_opts[:url] = api_path
    request_opts[:headers] = options[:headers] if options[:headers]
    request_opts[:params] = query_params
    request_opts[:payload] = payload # if [:post, :put].include?(request_opts[:method])
    @api_client.setopts(options)
      if options[:dry_run]
        print_dry_run @api_client.dry.execute(request_opts)
        return
      end
    json_response = @api_client.execute(request_opts)

    curl_object_key = json_response.keys.first
    render_response(json_response, options, curl_object_key) do
      # just render the json by default, non pretty..
      output = (json_response.is_a?(Hash) || json_response.is_a?(Array)) ? JSON.fast_generate(json_response) : json_response.to_s
      puts output
    end
    return 0, nil
  end

end
