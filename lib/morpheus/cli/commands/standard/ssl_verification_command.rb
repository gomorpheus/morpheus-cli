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

Set SSL Verification on or off.
Enable [on] or disable [off] SSL Verification.
If no arguments are passed, the current value is printed.
EOT
  end

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = usage
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    if args.count == 0
      puts Morpheus::RestClient.ssl_verification_enabled? ? "on" : "off"
      return Morpheus::RestClient.ssl_verification_enabled? ? 0 : 1
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
