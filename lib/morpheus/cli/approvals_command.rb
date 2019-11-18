require 'morpheus/cli/cli_command'

class Morpheus::Cli::ApprovalsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'approvals'

  register_subcommands :list, :get, :approve, :deny, :cancel
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @approvals_interface = @api_client.approvals
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List approvals."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      params.merge!(parse_list_options(options))
      @approvals_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @approvals_interface.dry.list(params)
        return
      end
      json_response = @approvals_interface.list(params)

      render_result = render_with_format(json_response, options, 'approvals')
      return 0 if render_result

      title = "Morpheus Approvals"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      approvals = json_response['approvals']
      if approvals.empty?
        print yellow,"No approvals found.",reset,"\n"
      else
        rows = approvals.collect do |it|
          {
              id: it['id'],
              name: it['name'] || (it['accountIntegration'] ? 'Pending' : 'Not Set'),
              requestType: it['requestType'],
              externalName: it['accountIntegration'] ? it['approval']['externalName'] || 'Pending' : 'N/A',
              type: it['accountIntegration'] ? it['accountIntegration']['type'] : 'Internal',
              status: it['status'],
              dateCreated: format_local_dt(it['dateCreated']),
              requestedBy: it['requestBy']
          }
        end
        columns = [
            :id, :name, :requestType, :externalName, :type, :status, :dateCreated, :requestedBy
        ]
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
        print reset,"\n"
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[approval]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a job.\n" +
          "[approval] is required. Approval ID or name"
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    return _get(args[0], options)
  end

  def _get(approval_id, options = {})
    params = {}
    begin
      @approvals_interface.setopts(options)

      if !(approval_id.to_s =~ /\A\d{1,}\Z/)
        approval = find_approval_by_name_or_id('approval', approval_id)

        if !approval
          print_red_alert "Approval #{approval_id} not found"
          exit 1
        end
        approval_id = approval['id']
      end

      if options[:dry_run]
        print_dry_run @approvals_interface.dry.get(approval_id, params)
        return
      end
      json_response = @approvals_interface.get(approval_id, params)

      render_result = render_with_format(json_response, options, 'approval')
      return 0 if render_result

      title = "Morpheus Approval"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      approval = json_response['approval']
      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name'] || (it['accountIntegration'] ? 'Pending' : 'Not Set')},
          "Request Type" => lambda {|it| it['requestType']},
          "External Name" => lambda {|it|it['accountIntegration'] ? it['approval']['externalName'] || 'Pending' : 'N/A'},
          "Type" => lambda {|it| it['accountIntegration'] ? it['accountIntegration']['type'] : 'Internal'},
          "Date Created" => lambda {|it| format_local_dt(it['dateCreated'])},
          "Requested By" => lambda {|it| it['requestBy']}
      }
      print_description_list(description_cols, approval)

      print_h2 "Requested Items"
      approval_items = approval['approvalItems']
      rows = approval_items.collect do |it|
        {
            id: it['id'],
            name: it['name'] || 'Not Set',
            external_name: it['externalName'] || 'N/A',
            reference: it['reference'] ? it['reference']['displayName'] || it['reference']['name'] : '',
            status: (it['status'] || '').capitalize,
            created: format_local_dt(it['dateCreated']),
            updated: format_local_dt(it['lastUpdated'])
        }
      end
      columns = [
          :name, :external_name, :reference, :status, :created, :updated
      ]
      print as_pretty_table(rows, columns, options)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def approve(args)
    return _update_item(args, 'approve')
  end

  def deny(args)
    return _update_item(args, 'deny')
  end

  def cancel(args)
    return _update_item(args, 'cancel')
  end

  def _update_item(args, action)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[id]")
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
      opts.footer = "#{action.capitalize} item.\n[id] is required. Approval item ID"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      approval_item = @approvals_interface.get_item(args[0].to_i)['approvalItem']

      if !approval_item
        print_red_alert "Approval item #{args[0]} not found"
        exit 1
      end

      @approvals_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @approvals_interface.dry.update_item(approval_item['id'], action)
        return
      end
      json_response = @approvals_interface.update_item(approval_item['id'], action)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Approval item #{action} applied"
          _get(approval_item['approval']['id'])
        else
          print_red_alert "Error updating approval item: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_approval_by_name_or_id(type, val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @approvals_interface.get(val.to_i)[typeCamelCase] : @approvals_interface.list({'name' => val})["approvals"].first
  end
end
