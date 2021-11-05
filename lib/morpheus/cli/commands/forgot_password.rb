require 'morpheus/cli/cli_command'

class Morpheus::Cli::ForgotPassword
  include Morpheus::Cli::CliCommand
  
  set_command_name :'forgot'
  set_command_description "Send a forgot password email and reset your password."

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @forgot_interface = @api_client.forgot
  end

  def handle(args)
  #   handle_subcommand(args)
  # end

  # def email(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} #{command_name} [username]"
      opts.on( '-U', '--username USERNAME', "Username of the user to be emailed." ) do |val|
        options[:options]['username'] = val
      end
      opts.on("--email [USERNAME]", String, "Email only. Only send an email, skip the reset password.") do |val|
        options[:email_only] = true
        if !val.to_s.empty?
          options[:options]['username'] = val
        end
      end
      opts.on("--reset [TOKEN]", "Reset only. Only reset password, skip sending an email.") do |val|
        options[:reset_only] = true
        if !val.to_s.empty?
          options[:options]['token'] = val
        end
      end
      opts.on( '-T', '--token TOKEN', "Token, the secret token that was emailed to the user. Only reset password, skip sending an email." ) do |val|
        options[:reset_only] = true
        options[:options]['token'] = val
      end
      opts.on( '-P', '--password PASSWORD', "New Password, the new password for the user." ) do |val|
        options[:options]['password'] = val
      end

      build_standard_post_options(opts, options, [], [:remote_username,:remote_password,:remote_token])
      opts.footer = <<-EOT
Send a forgot password email and reset your password.
[username] is required. This is the username to be notified.
By default this command prompts to perform two actions. 
First it sends a forgot password email to the specified user.
Then it attempts to reset the password with the secret token and a new password.
Use the --email and --token options to only perform one of these actions, instead of prompting to do both.
That is, only send the email or only reset the password.

EOT
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, max:1)

    if options[:email_only] && options[:options]['token']
      raise_command_error "Invalid usage. --email cannot be used with --token or --reset, use one or the other", args, optparse
    end

    if args[0]
      options[:options]['username'] = args[0]
    end
    
    params.merge!(parse_query_options(options))

    # Step 1. Send Forgot Password Email
    if options[:reset_only] != true
      print_h1 "Forgot Password", [], options unless options[:quiet] || options[:json] || options[:yaml]
      payload = {}
      payload['username'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'description' => "Enter the username of your Morpheus User.", 'required' => true, :fmt => :natural}], options[:options],@api_client)['username']
      @forgot_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @forgot_interface.dry.send_email(payload, params)
        return
      end
      json_response = @forgot_interface.send_email(payload, params)
      if options[:email_only]
        render_response(json_response, options) do
          print_green_success(json_response["msg"] || "Email has been sent") unless options[:quiet]
        end
        return 0, nil
      else
        print_green_success(json_response["msg"] || "Email has been sent") unless options[:quiet]
      end
    end

    # Step 2. Reset Password
    print_h1 "Reset Password", [], options unless options[:quiet] || options[:json] || options[:yaml]
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
      # prompt for Token
      payload['token'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'token', 'fieldLabel' => 'Token', 'type' => 'text', 'description' => "Enter the token that you obtained from the forgot password email.", 'required' => true, :fmt => :natural}], options[:options],@api_client)['token']
      # New Password
      # todo: prompt_password_with_confirmation()
      password_value = options[:options]['password']
      confirm_password_value = password_value
      while password_value.to_s.empty?
        password_value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'password', 'fieldLabel' => 'New Password', 'type' => 'password', 'description' => "Enter your new password.", 'required' => true, :fmt => :natural}], options[:options],@api_client)['password']
        confirm_password_value = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'password', 'fieldLabel' => 'Confirm New Password', 'type' => 'password', 'description' => "Enter your new password again to confirm it is what you intend.", 'required' => true, :fmt => :natural}], options[:options],@api_client)['password']
        if password_value != confirm_password_value
          print_red_alert("Passwords did not match. Please try again.")
          password_value = nil
        end
      end
      payload['password'] = password_value
    end
    
    @forgot_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @forgot_interface.dry.reset_password(payload, params)
      return
    end
    json_response = @forgot_interface.reset_password(payload, params)
    render_response(json_response, options) do
      print_green_success(json_response["msg"] || "Password has been updated") unless options[:quiet]
    end
    return 0, nil
  end

  protected

end

