require 'optparse'
require 'morpheus/rest_client'
require 'morpheus/cli/cli_command'
require 'json'

# This is for use in dotfile scripts
class Morpheus::Cli::SslVerificationCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'ssl-verification'
  set_command_hidden
def usage
    <<-EOT
Usage: morpheus #{command_name} [on|off]
\tThis is intended for use in your morpheus scripts.
\t"Enable [on] or Disable [off] SSL Verification for all your api requests."
\tThe default is on.
EOT
  end

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = usage
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
    end
    optparse.parse!(args)
    if args.count == 0
      puts Morpheus::RestClient.ssl_verification_enabled? ? "on" : "off"
      return true
    end
    if args.count > 1
      puts optparse
      return false
    end
    if ["on", "enabled", "true", "1"].include?(args[0].to_s.strip.downcase)
      Morpheus::RestClient.enable_ssl_verification = true
    elsif ["off", "disabled", "false", "0"].include?(args[0].to_s.strip.downcase)
      Morpheus::RestClient.enable_ssl_verification = false
    else
      puts optparse
      return false
    end
    return true
  end
end
