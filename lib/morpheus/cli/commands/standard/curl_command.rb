require 'optparse'
require 'morpheus/logging'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::CurlCommand
  include Morpheus::Cli::CliCommand
  set_command_name :curl
  set_command_hidden

  def handle(args)
    split_args = args.join(" ").split(" -- ")
    args = split_args[0].split(" ")
    curl_args = split_args[1] ? split_args[1].split(" ") : []
    curl_method = nil
    curl_data = nil
    show_progress = false
    # puts "args is : #{args}"
    # puts "curl_args is : #{curl_args}"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus curl [path] -- [*args]"
      opts.on( '-p', '--pretty', "Print result as parsed JSON." ) do
        options[:pretty] = true
      end
      opts.on( '-X', '--request METHOD', "HTTP request method. Default is GET" ) do |val|
        curl_method = val
      end
      opts.on( '--data DATA', String, "HTTP request body for use with POST and PUT, typically JSON." ) do |val|
        curl_data = val
      end
      opts.on( '--progress', '--progress', "Display progress output by excluding the -s option." ) do
        show_progress = true
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.add_hidden_option('--curl')
      #opts.add_hidden_option('--scrub')
      opts.footer = <<-EOT
This invokes the `curl` command with url "appliance_url/$0
and includes the authorization header -H "Authorization: Bearer access_token"
Arguments for the curl command should be passed after ' -- '
Example: morpheus curl "/api/servers/1" -- -XGET -sv

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
      curl_args.unshift "--insecure"
    end

    if !@appliance_url
      raise "Unable to determine remote appliance url"
      print "#{red}Unable to determine remote appliance url.#{reset}\n"
      return false
    end

    # determine curl url
    url = nil
    api_path = args[0].to_s.strip
    # allow absolute path for the current appliance url only
    if api_path.match(/^#{Regexp.escape(@appliance_url)}/)
      url = api_path
    else
      api_path = api_path.sub(/^\//, "") # strip leading slash
      url = "#{@appliance_url.chomp('/')}/#{api_path}"
    end
    curl_cmd = "curl"
    if show_progress == false
      curl_cmd << " -s"
    end
    if curl_method
      curl_cmd << " -X#{curl_method}"
    end
    curl_cmd << " \"#{url}\""
    if @access_token
      curl_cmd << " -H \"Authorization: Bearer #{@access_token}\""
    end
    if curl_data
      #todo: curl_data.gsub("'","\\'")
      curl_cmd << " --data '#{curl_data}'"
    end
    if !curl_args.empty?
      curl_cmd << " " + curl_args.join(' ')
    end
    
    # Morpheus::Logging::DarkPrinter.puts "#{curl_cmd}" if Morpheus::Logging.debug?
    curl_cmd_str = options[:scrub] ? Morpheus::Logging.scrub_message(curl_cmd) : curl_cmd

    if options[:dry_run]
      print cyan
      print "#{cyan}#{curl_cmd_str}#{reset}"
      print "\n\n"
      print reset
      return 0
    end
    # print cyan
    # print "#{cyan}#{curl_cmd_str}#{reset}"
    # print "\n\n"
    print reset
    # print result
    curl_output = `#{curl_cmd}`
    if options[:pretty]
      output_lines = curl_output.split("\n")
      last_line = output_lines.pop
      if output_lines.size > 0
        puts output_lines.join("\n")
      end
      begin
        json_data = JSON.parse(last_line)
        json_string = JSON.pretty_generate(json_data)
        puts json_string
      rescue => ex
        Morpheus::Logging::DarkPrinter.puts "failed to parse curl result as JSON data Error: #{ex.message}" if Morpheus::Logging.debug?
        puts last_line
      end
    else
      puts curl_output
    end
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
