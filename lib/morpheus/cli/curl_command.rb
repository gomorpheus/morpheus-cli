require 'optparse'
require 'morpheus/logging'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::CurlCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'curl'
  set_command_hidden

  def handle(args)
    split_args = args.join(" ").split(" -- ")
    args = split_args[0].split(" ")
    curl_args = split_args[1] ? split_args[1].split(" ") : []
    # puts "args is : #{args}"
    # puts "curl_args is : #{curl_args}"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: curl [path] -- [*args]"
      build_common_options(opts, options, [:remote])
      build_common_options(opts, options, [:remote])

      opts.footer = <<-EOT
This invokes the `curl` command with url "appliance_url/api/$0
and includes the authorization header -H "Authorization: Bearer access_token"
Arguments for the curl command should be passed after ' -- '
Example: morpheus curl "/api/servers/1" -- -XGET -sV

EOT
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return false
    end
    
    if !command_available?("curl")
      print "#{red}The 'curl' command is not available on your system.#{reset}\n"
      return false
    end
    
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true}))

    if !@appliance_name
      print yellow,"Please specify a Morpheus Appliance with -r or see the command `remote use`#{reset}\n"
      return false
    end

    # curry --insecure to curl
    if options[:insecure] || !Morpheus::RestClient.ssl_verification_enabled?
      #curl_args.unshift "-k"
      curl_args.unshift "--inescure"
    end

    creds = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
    if !creds
      print yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
      print yellow,"Use the 'login' command.",reset,"\n"
      return 0
    end

    if !@appliance_url
      raise "Unable to determine remote appliance url"
      print "#{red}Unable to determine remote appliance url.#{reset}\n"
      return false
    end

    # determine curl url
    base_url = @appliance_url.chomp("/")
    api_path = args[0].sub(/^\//, "")
    url = "#{base_url}/#{api_path}"
    curl_cmd = "curl \"#{url}\""
    curl_cmd << " -H \"Authorization: Bearer #{@access_token}\""
    if !curl_args.empty?
      curl_cmd << " " + curl_args.join(' ')
    end
    
    # Morpheus::Logging::DarkPrinter.puts "#{curl_cmd}" if Morpheus::Logging.debug?
    print cyan
    print "#{cyan}#{curl_cmd}#{reset}"
    print "\n\n"
    print reset
    # print result
    curl_output = `#{curl_cmd}`
    puts curl_output
    return $?.success?

  end

  def command_available?(cmd)
    has_it = false
    begin
      system("which #{cmd} > /dev/null 2>&1")
      has_it = $?.success?
    rescue => e
      raise e
    end
    return has_it
  end

end
