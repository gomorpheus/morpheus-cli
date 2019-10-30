require 'morpheus/cli/cli_command'

class Morpheus::Cli::WhitelabelSettingsCommand
  include Morpheus::Cli::CliCommand
 # include Morpheus::Cli::AccountsHelper

  set_command_name :'whitelabel-settings'

  register_subcommands :get, :update
  register_subcommands :update_images, :reset_image, :download_image, :view_image
  set_default_subcommand :get

  set_command_hidden # hiding until 4.2 release

  def initialize()
    @image_types = {'header-logo' => 'headerLogo', 'footer-logo' => 'footerLogo', 'login-logo' => 'loginLogo', 'favicon' => 'favicon'}
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @whitelabel_settings_interface = @api_client.whitelabel_settings
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--details', "Show full (not truncated) contents of Terms of Use, Privacy Policy, Override CSS" ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get whitelabel settings."
    end

    optparse.parse!(args)
    connect(options)

    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    
    begin
      params = parse_list_options(options)
      @whitelabel_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whitelabel_settings_interface.dry.get()
        return
      end
      json_response = @whitelabel_settings_interface.get()
      if options[:json]
        puts as_json(json_response, options, "whitelabelSettings")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "whitelabelSettings")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['whitelabelSettings']], options)
        return 0
      end

      whitelabel_settings = json_response['whitelabelSettings']

      print_h1 "Whitelabel Settings"
      print cyan
      description_cols = {
        "Enabled" => lambda {|it| format_boolean(it['enabled']) },
        "Appliance Name" => lambda {|it| it['applianceName'] },
        "Disable Support Menu" => lambda {|it| format_boolean(it['disableSupportMenu'])},
        "Header Logo" => lambda {|it| it['headerLogo'] ? it['headerLogo'].split('/').last : '' },
        "Footer Logo" => lambda {|it| it['footerLogo'] ? it['footerLogo'].split('/').last : '' },
        "Login Logo" => lambda {|it| it['loginLogo'] ? it['loginLogo'].split('/').last : '' },
        "Favicon" => lambda {|it| it['favicon'] ? it['favicon'].split('/').last : '' },
        "Header Background" => lambda {|it| it['headerBgColor']},
        "Header Foreground" => lambda {|it| it['headerFgColor']},
        "Nav Background" => lambda {|it| it['navBgColor']},
        "Nav Foreground" => lambda {|it| it['navFgColor']},
        "Nav Hover" => lambda {|it| it['navHoverColor']},
        "Primary Button Background" => lambda {|it| it['primaryButtonBgColor']},
        "Primary Button Foreground" => lambda {|it| it['primaryButtonFgColor']},
        "Primary Button Hover Background" => lambda {|it| it['primaryButtonHoverBgColor']},
        "Primary Button Hover Foreground" => lambda {|it| it['primaryButtonHoverFgColor']},
        "Footer Background" => lambda {|it| it['footerBgColor']},
        "Footer Foreground" => lambda {|it| it['footerFgColor']},
        "Login Background" => lambda {|it| it['loginBgColor']},
        "Copyright String" => lambda {|it| it['copyrightString']}
      }

      print_description_list(description_cols, whitelabel_settings)

      # Support Menu Links
      if !whitelabel_settings['supportMenuLinks'].empty?
        print_h2 "Support Menu Links"
        print cyan
        print as_pretty_table(whitelabel_settings['supportMenuLinks'], [:url, :label, :labelCode])
      end

      trunc_len = 80
      if !(content = whitelabel_settings['overrideCss']).nil? && content.length
        title = "Override CSS"
        title = title + ' (truncated, use --details for all content)' if content && content.length > trunc_len && !options[:details]
        print_h2 title
        print cyan
        print options[:details] ? content : truncate_string(content, trunc_len), "\n"
      end
      if !(content = whitelabel_settings['termsOfUse']).nil? && content.length
        title = "Terms of Use"
        title = title + ' (truncated, use --details for all content)' if content && content.length > trunc_len && !options[:details]
        print_h2 title
        print cyan
        print options[:details] ? content : truncate_string(content, trunc_len), "\n"
      end
      if !(content = whitelabel_settings['privacyPolicy']).nil? && content.length
        title = "Privacy Policy"
        title = title + ' (truncated, use --details for all content)' if content && content.length > trunc_len && !options[:details]
        print_h2 title
        print cyan
        print options[:details] ? content : truncate_string(content, trunc_len), "\n"
      end
      print reset "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      opts.on('--active [on|off]', String, "Can be used to enable / disable whitelabel feature") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--appliance-name NAME", String, "Appliance name. Only available to master account") do |val|
        params['applianceName'] = val == 'null' ? nil : val
      end
      opts.on("--disable-support-menu [on|off]", ['on','off'], "Can be used to disable support menu") do |val|
        params['disableSupportMenu'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--reset-header-logo", String, "Resets header logo to default header logo") do |val|
        params['resetHeaderLogo'] = true
      end
      opts.on("--reset-footer-logo", String, "Resets footer logo to default footer logo") do |val|
        params['resetFooterLogo'] = true
      end
      opts.on("--reset-login-logo", String, "Resets login logo to default login logo") do |val|
        params['resetLoginLogo'] = true
      end
      opts.on("--reset-favicon", String, "Resets favicon default favicon") do |val|
        params['resetFavicon'] = true
      end
      opts.on("--header-bg-color VALUE", String, "Header background color") do |val|
        params['headerBgColor'] = val
      end
      opts.on("--header-fg-color VALUE", String, "Header foreground color") do |val|
        params['headerFgColor'] = val
      end
      opts.on("--nav-bg-color VALUE", String, "Nav background color") do |val|
        params['navBgColor'] = val
      end
      opts.on("--nav-fg-color VALUE", String, "Nav foreground color") do |val|
        params['navFgColor'] = val
      end
      opts.on("--nav-hover-color VALUE", String, "Nav hover color") do |val|
        params['navHoverColor'] = val
      end
      opts.on("--primary-button-bg-color VALUE", String, "Primary button background color") do |val|
        params['primaryButtonBgColor'] = val
      end
      opts.on("--primary-button-fg-color VALUE", String, "Primary button foreground color") do |val|
        params['primaryButtonFgColor'] = val
      end
      opts.on("--primary-button-hover-bg-color VALUE", String, "Primary button hover background color") do |val|
        params['primaryButtonHoverBgColor'] = val
      end
      opts.on("--primary-button-hover-fg-color VALUE", String, "Primary button hover foreground color") do |val|
        params['primaryButtonHoverFgColor'] = val
      end
      opts.on("--footer-bg-color VALUE", String, "Footer background color") do |val|
        params['footerBgColor'] = val
      end
      opts.on("--footer-fg-color VALUE", String, "Footer foreground color") do |val|
        params['footerFgColor'] = val
      end
      opts.on("--login-bg-color VALUE", String, "Login background color") do |val|
        params['loginBgColor'] = val
      end
      opts.on("--copyright TEXT", String, "Copyright String") do |val|
        params['copyrightString'] = val
      end
      opts.on("--css TEXT", String, "Override CSS") do |val|
        params['overrideCss'] = val
      end
      opts.on("--css-file FILE", String, "Override CSS from local file") do |val|
        options[:overrideCssFile] = val
      end
      opts.on("--terms TEXT", String, "Terms of use content") do |val|
        params['termsOfUse'] = val
      end
      opts.on("--terms-file FILE", String, "Terms of use content from local file") do |val|
        options[:termsOfUseFile] = val
      end
      opts.on("--privacy-policy TEXT", String, "Privacy policy content") do |val|
        params['privacyPolicy'] = val
      end
      opts.on("--privacy-policy-file FILE", String, "Privacy policy content from local file") do |val|
        options[:privacyPolicyFile] = val
      end
      opts.on('--support-menu-links LIST', Array, "Support menu links. Comma delimited list of menu links. Each menu link is pipe delimited url1|label1|code1,url2|label2|code2") do |val|
        options[:supportMenuLinks] = val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end

    optparse.parse!(args)
    connect(options)

    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)
      image_files = {}

      if !payload
        [:overrideCssFile, :termsOfUseFile, :privacyPolicyFile].each do |sym|
          if options[sym]
            filename = File.expand_path(options[sym])

            if filename && File.file?(filename)
              params[sym.to_s.delete_suffix('File')] = File.read(filename)
            else
              print_red_alert("File not found: #{filename}")
              exit 1
            end
          end
        end
        if options[:supportMenuLinks]
          params['supportMenuLinks'] = options[:supportMenuLinks].collect { |link|
            parts = link.split('|')
            {'url' => parts[0].strip, 'label' => (parts.count > 1 ? parts[1].strip : ''), 'labelCode' => (parts.count > 2 ? parts[2].strip : '')}
          }
        end
        payload = {'whitelabelSettings' => params}
      end

      @whitelabel_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whitelabel_settings_interface.dry.update(payload, image_files)
        return
      end
      json_response = @whitelabel_settings_interface.update(payload, image_files)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Updated whitelabel settings"
          get([] + (options[:remote] ? ["-r",options[:remote]] : []))
        else
          print_red_alert "Error updating whitelabel settings: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_images(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage()
      opts.on("--header-logo FILE", String, "Header logo image. Local path of a file to upload (png|jpg|svg)") do |val|
        options[:headerLogo] = val
      end
      opts.on("--reset-header-logo", String, "Resets header logo to default header logo") do |val|
        params['resetHeaderLogo'] = true
      end
      opts.on("--footer-logo FILE", String, "Footer logo image. Local path of a file to upload (png|jpg|svg)") do |val|
        options[:footerLogo] = val
      end
      opts.on("--reset-footer-logo", String, "Resets footer logo to default footer logo") do |val|
        params['resetFooterLogo'] = true
      end
      opts.on("--login-logo FILE", String, "Login logo image. Local path of a file to upload (png|jpg|svg)") do |val|
        options[:loginLogo] = val
      end
      opts.on("--reset-login-logo", String, "Resets login logo to default login logo") do |val|
        params['resetLoginLogo'] = true
      end
      opts.on("--favicon FILE", String, "Favicon icon image. Local path of a file to upload") do |val|
        options[:favicon] = val
      end
      opts.on("--reset-favicon", String, "Resets favicon default favicon") do |val|
        params['resetFavicon'] = true
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Update your whitelabel images."
    end

    optparse.parse!(args)
    connect(options)

    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)

      if !payload
        payload = params

        [:headerLogo, :footerLogo, :loginLogo, :favicon].each do |sym|
          if options[sym]
            filename = File.expand_path(options[sym])

            if filename && File.file?(filename)
              payload["#{sym.to_s}.file"] = File.new(filename, 'rb')
            else
              print_red_alert("File not found: #{filename}")
              exit 1
            end
          end
        end
      end

      if payload.empty?
        print_green_success "Nothing to update"
        exit 1
      end

      @whitelabel_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whitelabel_settings_interface.dry.update_images(payload)
        return
      end

      json_response = @whitelabel_settings_interface.update_images(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_red_alert "Error updating whitelabel image: #{json_response['msg'] || json_response['errors']}" if json_response['success'] == false
        print_green_success "Updated whitelabel image" if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def reset_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[image-type]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Reset your whitelabel image.\n" +
          "[image-type] is required. This is the whitelabel image type (#{@image_types.collect {|k,v| k}.join('|')})"
    end

    optparse.parse!(args)
    connect(options)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    if !@image_types[args[0]]
      raise_command_error "Invalid image type specified: #{args[0]}. Must be one of the following (#{@image_types.collect {|k,v| k}.join('|')})"
      return 1
    end

    begin
      image_type = @image_types[args[0]]
      @whitelabel_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whitelabel_settings_interface.dry.reset_image(image_type)
        return
      end

      json_response = @whitelabel_settings_interface.reset_image(image_type)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_red_alert "Error resetting whitelabel image: #{json_response['msg'] || json_response['errors']}" if json_response['success'] == false
        print_green_success "Reset whitelabel image" if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[image-type]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "View your image of specified [image-type].\n" +
          "[image-type] is required. This is the whitelabel image type (#{@image_types.collect {|k,v| k}.join('|')})\n" +
          "This opens the image url with a web browser."
    end

    optparse.parse!(args)
    connect(options)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    if !@image_types[args[0]]
      raise_command_error "Invalid image type specified: #{args[0]}. Must be one of the following (#{@image_types.collect {|k,v| k}.join('|')})"
      return 1
    end

    begin
      image_type = @image_types[args[0]]
      @whitelabel_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whitelabel_settings_interface.dry.get()
        return
      end

      whitelabel_settings = @whitelabel_settings_interface.get()['whitelabelSettings']

      if link = whitelabel_settings[image_type]
        if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
          system "start #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /darwin/
          system "open #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
          system "xdg-open #{link}"
        end
        return 0, nil
      else
        print_error red,"No image found for #{image_type}.",reset,"\n"
        return 1
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def download_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = opts.banner = subcommand_usage("[image-type] [local-file]")
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        options[:overwrite] = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        options[:mkdir] = true
      end
      build_common_options(opts, options, [:dry_run, :quiet, :remote])
      opts.footer = "Download an image file.\n" +
          "[image-type] is required. This is the whitelabel image type (#{@image_types.collect {|k,v| k}.join('|')}) to be downloaded.\n" +
          "[local-file] is required. This is the full local filepath for the downloaded file."
    end

    optparse.parse!(args)
    connect(options)

    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end
    if !@image_types[args[0]]
      raise_command_error "Invalid image type specified: #{args[0]}. Must be one of the following (#{@image_types.collect {|k,v| k}.join('|')})"
      return 1
    end

    begin
      image_type = @image_types[args[0]]
      outfile = File.expand_path(args[1])
      outdir = File.dirname(outfile)

      if Dir.exists?(outfile)
        print_red_alert "[local-file] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      if !Dir.exists?(outdir)
        if options[:mkdir]
          print cyan,"Creating local directory #{outdir}",reset,"\n"
          FileUtils.mkdir_p(outdir)
        else
          print_red_alert "[local-file] is invalid. Directory not found: #{outdir}"
          return 1
        end
      end
      if File.exists?(outfile) && !options[:overwrite]
        print_red_alert "[local-file] is invalid. File already exists: #{outfile}\nUse -f to overwrite the existing file."
        return 1
      end

      @whitelabel_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whitelabel_settings_interface.dry.download_image(image_type, outfile)
        return
      end

      if !options[:quite]
        print cyan + "Downloading #{args[0]} to #{outfile} ... "
      end

      http_response = @whitelabel_settings_interface.download_image(image_type, outfile)

      success = http_response.code.to_i == 200
      if success
        if !options[:quiet]
          print green + "SUCCESS" + reset + "\n"
        end
        return 0
      else
        if !options[:quiet]
          print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n"
        end
        if File.exists?(outfile) && File.file?(outfile)
          Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
          File.delete(outfile)
        end
        if options[:debug]
          puts_error http_response.inspect
        end
        return 1
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end
end
