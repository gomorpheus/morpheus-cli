require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::BudgetsCommand
  include Morpheus::Cli::CliCommand
  set_command_name :budgets
  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @budgets_interface = @api_client.budgets
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      # opts.on('--category VALUE', String, "Category") do |val|
      #   params['category'] = val
      # end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List budgets."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @budgets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @budgets_interface.dry.list(params)
        return 0
      end
      json_response = @budgets_interface.list(params)
      render_result = render_with_format(json_response, options, 'budgets')
      return 0 if render_result
      budgets = json_response['budgets']
      unless options[:quiet]
        title = "Morpheus Budgets"
        subtitles = []
        if params['category']
          subtitles << "Category: #{params['category']}"
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if budgets.empty?
          print yellow,"No budgets found.",reset,"\n"
        else
          columns = [
            {"ID" => lambda {|budget| budget['id'] } },
            {"NAME" => lambda {|budget| budget['name'] } },
            {"DESCRIPTION" => lambda {|budget| budget['description'] } },
            #{"REFERENCE" => lambda {|it| it['refType'] ? "#{it['refType']} (#{it['refId']}) #{it['refName']}".strip : '' } },
            {"CREATED BY" => lambda {|budget| budget['createdByName'] ? budget['createdByName'] : budget['createdById'] } },
            {"CREATED" => lambda {|budget| format_local_dt(budget['dateCreated']) } },
            {"UPDATED" => lambda {|budget| format_local_dt(budget['lastUpdated']) } },
          ]
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print as_pretty_table(budgets, columns, options)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[budget]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a budget.\n[budget] is required. Budget ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      @budgets_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @budgets_interface.dry.get(args[0])
        else
          print_dry_run @budgets_interface.dry.list({name: args[0].to_s})
        end
        return 0
      end
      budget = find_budget_by_name_or_id(args[0])
      return 1 if budget.nil?
      json_response = {'budget' => budget}
      render_result = render_with_format(json_response, options, 'budget')
      return 0 if render_result


      unless options[:quiet]
        print_h1 "Budget Details"
        print cyan
        budget_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          # "Period" => lambda {|it| it['period'].to_s },
          "Year" => lambda {|it| it['year'] },
          "Interval" => lambda {|it| it['interval'] },
          # "Costs" => lambda {|it| it['costs'] },
        }
        if budget['refType']
          budget_columns.merge!({
            "Scope" => lambda {|it| it['refType'] ? "#{it['refType']} (#{it['refId']}) #{it['refName']}".strip : '' },
          })
        end
        if budget['interval'] == 'year'
          budget_columns.merge!({
            "Annual" => lambda {|it| 
              (it['costs'] && it['costs'][0]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][0].to_s) : '' 
            },
          })
        elsif budget['interval'] == 'quarter'
          budget_columns.merge!({
            "First Quarter" => lambda {|it| (it['costs'] && it['costs'][0]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][0].to_s) : ''   },
            "Second Quarter" => lambda {|it| (it['costs'] && it['costs'][1]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][1].to_s) : ''  },
            "Third Quarter" => lambda {|it| (it['costs'] && it['costs'][2]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][2].to_s) : ''  },
            "Fourth Quarter" => lambda {|it| (it['costs'] && it['costs'][3]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][3].to_s) : ''  },
          })
        elsif budget['interval'] == 'month'
          budget_columns.merge!({
            "January" => lambda {|it| (it['costs'] && it['costs'][0]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][0].to_s) : ''  },
            "February" => lambda {|it| (it['costs'] && it['costs'][1]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][1].to_s) : ''  },
            "March" => lambda {|it| (it['costs'] && it['costs'][2]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][2].to_s) : ''  },
            "April" => lambda {|it| (it['costs'] && it['costs'][3]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][3].to_s) : ''  },
            "May" => lambda {|it| (it['costs'] && it['costs'][4]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][4].to_s) : ''  },
            "June" => lambda {|it| (it['costs'] && it['costs'][5]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][5].to_s) : ''  },
            "July" => lambda {|it| (it['costs'] && it['costs'][6]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][6].to_s) : ''  },
            "August" => lambda {|it| (it['costs'] && it['costs'][7]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][7].to_s) : ''  },
            "September" => lambda {|it| (it['costs'] && it['costs'][8]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][8].to_s) : ''  },
            "October" => lambda {|it| (it['costs'] && it['costs'][9]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][9].to_s) : ''  },
            "November" => lambda {|it| (it['costs'] && it['costs'][10]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][10].to_s) : ''  },
            "December" => lambda {|it| (it['costs'] && it['costs'][11]) ? format_amount(currency_sym(it['currency']).to_s + it['costs'][11].to_s) : ''  }
          })
        else
          budget_columns.merge!({
            "Costs" => lambda {|it| 
              it['costs'] ? it['costs'].join(', ') : '' 
            },
          })
        end
        budget_columns.merge!({
          "Created By" => lambda {|it| it['createdByName'] ? it['createdByName'] : it['createdById'] },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        })
        print_description_list(budget_columns, budget)
        print reset,"\n"

      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_budget_option_types)
      opts.on('--cost [amount]', String, "Budget Cost amount, for use with default interval of year.") do |val|
        list = (val.nil? || val.empty?) ? [] : [val.to_f]
        params['costs'] = list
      end
      opts.on('--costs [amount]', Array, "Budget Cost amounts, one for each interval. eg. [5000] for yearly or [99,99,99,99] for quarterly.") do |val|
        list = (val.nil? || val.empty?) ? [] : val
        val = val.collect {|it| it.to_s.empty? ? nil : it.to_f }
        params['costs'] = list
      end
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
      opts.footer = "Create budget."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options]['name'] ||= args[0]
    end
    connect(options)
    begin
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'budget' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
        # prompt for options
        v_prompt = Morpheus::Cli::OptionTypes.prompt(add_budget_option_types, options[:options], @api_client)
        params.deep_merge!(v_prompt)
        params['costs'] = prompt_costs(params, options)
        payload.deep_merge!({'budget' => params}) unless params.empty?
      end

      @budgets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @budgets_interface.dry.create(payload)
        return
      end
      json_response = @budgets_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['budget']  ? json_response['budget']['name'] : ''
        print_green_success "Budget #{display_name} added"
        get([json_response['budget']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[budget] [options]")
      build_option_type_options(opts, options, update_budget_option_types)
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
      opts.footer = "Update budget.\n[budget] is required. Budget ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin

      budget = find_budget_by_name_or_id(args[0])
      return 1 if budget.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'budget' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_budget_option_types, options[:options], @api_client, options[:params])
        params = passed_options

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
        if params["category"] && (params["category"].strip == "" || params["category"].strip == "null")
          params["category"] = ""
        end
        payload.deep_merge!({'budget' => params}) unless params.empty?
      end
      @budgets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @budgets_interface.dry.update(budget['id'], payload)
        return
      end
      json_response = @budgets_interface.update(budget['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['budget'] ? json_response['budget']['name'] : ''
        print_green_success "Budget #{display_name} updated"
        get([json_response['budget']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete budget.\n[budget] is required. Budget ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      budget = find_budget_by_name_or_id(args[0])
      return 1 if budget.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the budget #{budget['name']}?")
        return 9, "aborted command"
      end
      @budgets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @budgets_interface.dry.destroy(budget['id'])
        return
      end
      json_response = @budgets_interface.destroy(budget['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Budget #{budget['name']} removed"
        # list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_budget_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_budget_by_id(val)
    else
      return find_budget_by_name(val)
    end
  end

  def find_budget_by_id(id)
    raise "#{self.class} has not defined @budgets_interface" if @budgets_interface.nil?
    begin
      json_response = @budgets_interface.get(id)
      return json_response['budget']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Budget not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_budget_by_name(name)
    raise "#{self.class} has not defined @budgets_interface" if @budgets_interface.nil?
    budgets = @budgets_interface.list({name: name.to_s})['budgets']
    if budgets.empty?
      print_red_alert "Budget not found by name #{name}"
      return nil
    elsif budgets.size > 1
      print_red_alert "#{budgets.size} Budgets found by name #{name}"
      print as_pretty_table(budgets, [:id,:name], {color:red})
      print reset,"\n"
      return nil
    else
      return budgets[0]
    end
  end

  def add_budget_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'year', 'fieldLabel' => 'Year', 'type' => 'text', 'required' => true, 'defaultValue' => Time.now.year},
      {'fieldName' => 'interval', 'fieldLabel' => 'Interval', 'type' => 'select', 'selectOptions' => [{'name'=>'Year','value'=>'year'},{'name'=>'Quarter','value'=>'quarter'},{'name'=>'Month','value'=>'month'}], 'defaultValue' => 'year', 'required' => true}
    ]
  end

  def update_budget_option_types
    list = add_budget_option_types()
    # list = list.reject {|it| ["interval"].include? it['fieldName'] }
    list.each {|it| it['required'] = false }
    list
  end

  def prompt_costs(params={}, options={})
    interval = params['interval']
    options[:options]||={}
    costs = []
    costs_val = params['costs'] ? params['costs'] : options[:options]['costs']
    if costs_val.is_a?(Array)
      costs = costs_val
    elsif costs_val.is_a?(String)
      costs = costs_val.to_s.split(',').collect {|it| it.to_s.strip.to_f }
    else
      if interval == 'year'
        cost_option_types = [
          {'fieldName' => 'annual', 'fieldLabel' => 'Annual Cost', 'type' => 'text'}
        ]
        values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
        costs = [
          values['annual']
        ]
      elsif interval == 'quarter'
        cost_option_types = [
          {'fieldName' => 'quarter1', 'fieldLabel' => 'First Quarter', 'type' => 'text'},
          {'fieldName' => 'quarter2', 'fieldLabel' => 'Second Quarter', 'type' => 'text'},
          {'fieldName' => 'quarter3', 'fieldLabel' => 'Third Quarter', 'type' => 'text'},
          {'fieldName' => 'quarter4', 'fieldLabel' => 'Fourth Quarter', 'type' => 'text'}
        ]
        values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
        costs = [
          values['quarter1'],values['quarter2'],values['quarter3'],values['quarter4']
        ]
      elsif interval == 'month'
        cost_option_types = [
          {'fieldName' => 'january', 'fieldLabel' => 'January', 'type' => 'text'},
          {'fieldName' => 'february', 'fieldLabel' => 'Frebruary', 'type' => 'text'},
          {'fieldName' => 'march', 'fieldLabel' => 'March', 'type' => 'text'}
        ]
        values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
        costs = [
          values['january'],values['february'],values['march'],
          values['april'],values['may'],values['june'],
          values['july'],values['august'],values['september'],
          values['october'],values['november'],values['december']
        ]
      end
    end
    return costs
  end

  def currency_sym(currency)
    Money::Currency.new((currency || 'usd').to_sym).symbol
  end

  def format_amount(amount)
    rtn = amount.to_s
    if rtn.index('.').nil?
      rtn += '.00'
    elsif rtn.split('.')[1].length < 2
      rtn = rtn + (['0'] * (2 - rtn.split('.')[1].length) * '')
    end
    rtn
  end

end
