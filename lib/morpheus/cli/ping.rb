# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/whoami_helper'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Ping
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RemoteHelper

  set_command_name :ping

  def connect(options={})
    @api_client = establish_remote_appliance_connection({:no_authorization => true}.merge(options))
    @ping_interface = @api_client.ping
    @setup_interface = @api_client.setup
  end

  def handle(args)
    get(args)
  end

  def get(args)
    exit_code, err = 0, nil
    params, options = {}, {}
    status_only, time_only, setup_check_only = false, false, false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on( '-s', '--status', "Print only the status." ) do
        status_only = true
      end
      opts.on( '-t', '--time', "Print only the response time." ) do
        time_only = true
      end
      opts.on( '--setup-needed?', "Print only if setup is needed or not, exit 1 if not." ) do
        setup_check_only = true
      end
      # --timeout always works, this would just make it show up?
      # opts.on( '--timeout SECONDS', "Timeout for api requests. Default is 5 seconds." ) do |val|
      #   options[:timeout] = val ? val.to_f : nil
      #   # note that setting :timeout works via interface.setopts(options)
      # end
      build_standard_get_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Ping the remote morpheus appliance.
Prints the remote version and status and the time it took to get a response.

EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, count:0, optparse:optparse)
    connect(options)
    took_sec = nil
    begin
      # construct parameters
      params.merge!(parse_query_options(options))

      # error if we could not determine a remote, this should happen by in connect()
      # if !@remote_appliance
      #   raise_command_error "#{command_name} requires a remote to be specified, use -r [remote] or set the active remote with `remote use`"
      # end
      appliance = @remote_appliance
      
      # set api client options
      @ping_interface.setopts(options)
      @setup_interface.setopts(options)

      # dry run, print the would be request
      if options[:dry_run]
        print_dry_run @ping_interface.dry.get(params)
        return 0
      end
      # execute the api request
      # /api/ping is new in 4.2.1, so fallback to /api/setup/check, the data is the same-ish
      api_exception = nil
      json_response = nil
      start_time = Time.now
      begin
        json_response = @ping_interface.get(params)
      rescue RestClient::Exception => e
        # api_exception = e
        # fallback to older /api/setup/check, which is also public and looks just about the same
        if e.response.code == 404
          start_time = Time.now
          begin
            json_response = @setup_interface.check(params)
          rescue RestClient::Exception => e2
            begin
              json_response = JSON.parse(e2.response.to_s)
            rescue TypeError, JSON::ParserError => ex
              #print_error red, "Failed to parse JSON response: #{ex}", reset, "\n"
              json_response = nil
            end
          end
        end
      rescue => e
        api_exception = e
      ensure
        took_sec = (Time.now - start_time)
      end

      # update appliance settings with /ping response (or /setup/check) ie. buildVersion
      # this also happens in save_remote_last_check() but remote_url doesnt use that
      if json_response
        # update buildVersion
        if json_response['buildVersion']
          appliance[:build_version] = json_response['buildVersion']
        end
        # update applianceUrl
        if json_response['applianceUrl']
          appliance[:appliance_url] = json_response['applianceUrl']
        end
        # set status to ready if we have a version but no status yet for some reason
        if appliance[:build_version] && appliance[:status].nil?
          appliance[:status] = 'ready'
        end
        # update setupNeeded? 
        if json_response['setupNeeded'] == true
          # appliance[:setup_needed] = true
          appliance[:status] = 'fresh'
        end
        # if took_sec
        #   appliance[:last_check] ||= {}
        #   appliance[:last_check][:took] = took_sec
        # end
      else
        # appliance[:status] = 'error'
      end

      # don't ever save with --remote-url
      if options[:remote_url].nil?
        # save response to appliance data
        Morpheus::Cli::Remote.save_remote_last_check(appliance, json_response, api_exception, took_sec)
        # reload needed?
        # appliance = ::Morpheus::Cli::Remote.appliances[@appliance_name.to_sym]
        appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
      end
      
      # determine exit status, 0 is good
      exit_code, err = 0, nil
      if appliance[:status] != 'ready' && appliance[:status] != 'fresh'
        exit_code = 1
        # err = appliance[:error]
      end
      
      # render
      render_response(json_response, options) do
        if json_response.nil?
          json_response = {}
        end
        if false && json_response.nil?
          print_error yellow, "No ping data returned.",reset,"\n"
        else
          # print output
          if status_only
            if exit_code == 0
              print format_appliance_status(appliance, cyan), reset, "\n"
            else
              print_error format_appliance_status(appliance, cyan), reset, "\n"
            end
            return exit_code, err
          elsif time_only
            status_color = format_appliance_status_color(appliance)
            if exit_code == 0
              print status_color, format_duration_seconds(took_sec), reset, "\n"
            else
              print_error status_color, format_duration_seconds(took_sec), reset, "\n"
            end
            return exit_code, err
          elsif setup_check_only
            status_color = format_appliance_status_color(appliance)
            remote_status_string = format_appliance_status(appliance, cyan)
            if appliance[:status] != 'fresh'
              exit_code = 1
            end
            if appliance[:status] == 'fresh'
              print cyan, "Yes, remote #{appliance[:name]} status is #{remote_status_string}","\n"
            elsif appliance[:status] == 'ready'
              print cyan, "No, remote #{appliance[:name]} status is #{remote_status_string} (already setup)","\n"
            else
              print_error cyan,"Uh oh, remote #{appliance[:name]} status is #{remote_status_string}",reset,"\n"
            end
            return exit_code, err
          else
            title = "Morpheus Ping"
            subtitles = []
            print_h1 title, subtitles, options
            #print_green_success "Completed ping of #{appliance[:name]} (#{format_duration_seconds(took_sec)})"
            #print "\n"
            error_string = appliance[:last_check] ? appliance[:last_check][:error] : nil
            columns = {
              "Name" => lambda {|it| appliance[:name] },
              #"Name" => lambda {|it| appliance[:active] ? "#{appliance[:name]} #{bold}(current)#{reset}#{cyan}" : appliance[:name] },
              "URL" => lambda {|it| appliance[:url] },
              #"Appliance URL" => lambda {|it| it['applianceUrl'] },
              "Version" => lambda {|it| appliance[:build_version] },
              # "Active" => lambda {|it| it[:active] ? "Yes " + format_is_current() : "No" },
              "Response Time" => lambda {|it| format_duration_seconds(took_sec) },
              #"Response Time" => lambda {|it| format_sig_dig(took_sec, 3) + "s" rescue "" },
              # "Error" => lambda {|it| error_string },
              "Status" => lambda {|it| format_appliance_status(appliance, cyan) },
            }
            if error_string.to_s.empty?
              columns.delete("Error")
            end

            print_description_list(columns, json_response, options)

            if error_string.to_s != ""
              #print_h2 "Error", options
              print "\n"
              print red, error_string, "\n",reset
            end
          end
          print reset, "\n"
        end
      end
      return exit_code, err


    rescue RestClient::Exception => e
      # don't ever save with --remote-url
      if options[:remote_url].nil?
        # save response to appliance data
        Morpheus::Cli::Remote.save_remote_last_check(appliance, json_response, e, took_sec)
        # reload?
        appliance = ::Morpheus::Cli::Remote.load_remote(appliance[:name])
      end
      # print output
      if status_only
        print format_appliance_status(appliance, cyan), reset, "\n"
        return exit_code, err
      elsif time_only
        status_color = format_appliance_status_color(appliance)
        print status_color, format_duration_seconds(took_sec), reset, "\n"
        return exit_code, err
      else
        if e.response
          print_red_alert "ping failed in #{format_duration_seconds(took_sec)} (HTTP #{e.response.code})"
        else
          print_red_alert "ping failed in #{format_duration_seconds(took_sec)}"
        end
      end
      print_rest_exception(e, options)
      return 1, e.message
    end
  end

end
