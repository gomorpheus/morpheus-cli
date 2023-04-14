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
        begin
          options[:payload] = JSON.parse(val.to_s)
        rescue => ex
          raise ::OptionParser::InvalidOption.new("Failed to parse payload as JSON. Error: #{ex.message}")
        end
      end
      opts.on('--absolute', "Absolute path, value can be used to prevent automatic using the automatic /api/ path prefix to the path by default.") do
        options[:absolute_path] = true
      end
      opts.on('--inspect', "Inspect response, prints headers. By default only the body is printed.") do
        options[:inspect_response] = true
      end
      build_standard_api_options(opts, options)
      opts.footer = <<-EOT
Execute an HTTP request against the remote appliance api to an arbitrary path.
[path] is required. This is the path to path to request. By default 
By default the "/api" prefix is included in the request path.
The --absolute option ban be used to supress this.

Examples: 
    morpheus curl "/api/whoami"
    morpheus curl whoami
    morpheus curl apps -r demo

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
    # by default /api/ prefix is prepended
    if options[:absolute_path] || api_path.start_with?("http:") || api_path.start_with?("https:")
      api_path = api_path
    else
      api_path = "/#{api_path}" unless api_path.start_with?("/")
      api_path = "/api#{api_path}" unless api_path.start_with?("/api")
    end
      
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
    request_opts[:parse_json] = false
    @api_client.setopts(options)
    if options[:dry_run]
      print_dry_run @api_client.dry.execute(request_opts)
      return
    end
    api_response = nil
    json_response = nil
    begin
      api_response = @api_client.execute(request_opts)
    rescue ::RestClient::Exception => e

      exit_code = 1
      err = e.message
      #raise e
      api_response = e.response
      # did not get a response?
      if api_response.nil?
        print_rest_exception(e, options)
        return 1, e.message
      end
    end
    if api_response.nil?
      print_rest_exception(e, options)
      return 1, e.message
    end
    response_is_ok = (api_response.code.to_i >= 200 && api_response.code.to_i < 400)
    response_is_json = api_response.headers[:content_type].to_s.start_with?("application/json")
    if response_is_json && options[:inspect_response] != true
      # render as json by default, so -f just works
      # options[:json] = true unless options[:csv] ||  options[:yaml]
      begin
        json_response = JSON.parse(api_response.body.to_s)
      rescue => e
        puts_error "Failed to parse response as JSON. Error: #{e}"
        # json_response = {}
      end
      # this should be default behavior, but use the first key if it is a Hash or Array
      object_key = nil
      if json_response && json_response.keys.first && [Hash,Array].include?(json_response[json_response.keys.first].class)
        object_key = json_response.keys.first
      end
      render_response(json_response, options, object_key) do
        output = ""
        output << red if !response_is_ok
        # just render the json by default, non pretty..
        output << JSON.fast_generate(json_response)
        output << "\n"
        output << reset
        if exit_code == 1
          print output
        elsif
          print_error output
        end
      end
    else
      output = ""
      output << red if !response_is_ok
      if options[:inspect_response]
        # instead http response (version and headers)
        output << "HTTP/#{api_response.net_http_res.http_version} #{api_response.code}\n"
        api_response.net_http_res.each_capitalized.each do |k,v|
          output << "#{k}: #{v}\n"
        end
        output << "\n"
        output << api_response.body.to_s
      else
        output << api_response.body.to_s
      end
      output << "\n"
      output << reset
      if exit_code == 0
        print output
      elsif
        print_error output
      end
    end
    return exit_code, err
  end

end
