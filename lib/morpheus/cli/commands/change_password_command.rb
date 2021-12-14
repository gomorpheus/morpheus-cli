require 'morpheus/cli/cli_command'

class Morpheus::Cli::ChangePasswordCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :passwd

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @whoami_interface = @api_client.whoami
    @account_users_interface = @api_client.account_users
    @accounts_interface = @api_client.accounts
    @roles_interface = @api_client.roles
  end

  def handle(args)
    change_password(args)
  end

  def change_password(args)
    options = {}
    username = nil
    new_password = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username] [options]")
      opts.on('--username USERNAME', String, "Username. Default is your own.") do |val|
        username = val
      end
      opts.on('--password VALUE', String, "New password") do |val|
        new_password = val
      end
      build_common_options(opts, options, [:account, :options, :json, :dry_run, :remote, :quiet, :auto_confirm], [:username,:password])
      opts.footer = "Change your password or the password of another user.\n" +
                    "[username] is optional. This is the username of the user to update. Default is your own.\n" +
                    "Be careful with this command, the default behavior is to update your own password."
    end
    optparse.parse!(args)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count} #{args}\n#{optparse}"
      return 1
    end

    connect(options)
    @current_remote = @appliance_name ? ::Morpheus::Cli::Remote.load_remote(@appliance_name) : ::Morpheus::Cli::Remote.load_active_remote()

    if args[0]
      username = args[0]
    end
    if username.nil?
      if !@current_remote
        raise_command_error "No current appliance, see `remote use`."
      end
      if !@current_remote[:username]
        raise_command_error "You are not currently logged in to #{display_appliance(@current_remote[:name], @current_remote[:url])}"
      end
      username = @current_remote[:username]
    end

    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil

    user = find_user_by_username_or_id(account_id, username)
    return 1 if user.nil?

    if @current_remote && @current_remote[:username] == username
      if !options[:quiet]
        if options[:dry_run]
          print cyan,bold,  "DRY RUN. This is just a dry run, the password is not being updated.",reset,"\n"
        else
          print cyan,bold,  "WARNING! You are about to update your own password!",reset,"\n"
          print yellow,bold,"WARNING! You are about to update your own password!",reset,"\n"
          print reset,bold, "WARNING! You are about to update your own password!",reset,"\n"
        end
      end
    end

    if !options[:quiet]
      print cyan, "Changing password for #{user['username']}", reset, "\n"
    end

    if new_password.nil? && options[:options]['password']
      new_password = options[:options]['password']
    end
    if new_password.nil?
      password_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'password', 'fieldLabel' => 'New Password', 'type' => 'password', 'required' => true}], options[:options], @api_client)
      new_password = password_prompt['password']
      confirm_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true}], options[:options], @api_client)
      confirm_password = confirm_prompt['passwordConfirmation']
      if confirm_password != new_password
        print_red_alert "Confirm password did not match."
        return 1
      end
    end

    if new_password.nil? || new_password.empty?
      print_red_alert "A new password is required"
      return 1
    end

    payload = {
      'user' => {
        'password' => new_password
      } 
    }
    @account_users_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @account_users_interface.dry.update(account_id, user['id'], payload)
      return 0
    end

    unless options[:yes]
      unless ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the password for user #{user['username']}?", options)
        return 9, "aborted command"
      end
    end

    json_response = @account_users_interface.update(account_id, user['id'], payload)
    if options[:json]
      puts as_json(json_response)
    elsif !options[:quiet]
      print_green_success "Updated password for user #{user['username']}"
    end
    return 0
  end

  private


end
