require 'morpheus/cli/cli_command'
require 'money' # ew, let's write our own

class Morpheus::Cli::BudgetsCommand
  include Morpheus::Cli::CliCommand
  set_command_name :budgets
  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @budgets_interface = @api_client.budgets
    @options_interface = @api_client.options
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
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if budgets.empty?
          print yellow,"No budgets found.",reset,"\n"
        else
          columns = [
            {"ID" => lambda {|budget| budget['id'] } },
            {"NAME" => lambda {|budget| budget['name'] } },
            {"DESCRIPTION" => lambda {|budget| truncate_string(budget['description'], 30) } },
            # {"ENABLED" => lambda {|budget| format_boolean(budget['enabled']) } },
            # {"SCOPE" => lambda {|it| format_budget_scope(it) } },
            {"SCOPE" => lambda {|it| it['refName'] } },
            {"PERIOD" => lambda {|it| it['year'] } },
            {"INTERVAL" => lambda {|it| it['interval'].to_s.capitalize } },
            # the UI doesn't consider timezone, so uhh do it this hacky way for now.
            {"START DATE" => lambda {|it| 
              if it['timezone'] == 'UTC'
                ((parse_time(it['startDate'], "%Y-%m-%d").strftime("%x")) rescue it['startDate']) # + ' UTC'
              else
                format_local_date(it['startDate']) 
              end
            } },
            {"END DATE" => lambda {|it| 
              if it['timezone'] == 'UTC'
                ((parse_time(it['endDate'], "%Y-%m-%d").strftime("%x")) rescue it['endDate']) # + ' UTC'
              else
                format_local_date(it['endDate']) 
              end
            } },
            {"TOTAL" => lambda {|it| format_money(it['totalCost'], it['currency']) } },
            {"AVERAGE" => lambda {|it| format_money(it['averageCost'], it['currency']) } },
            # {"CREATED BY" => lambda {|budget| budget['createdByName'] ? budget['createdByName'] : budget['createdById'] } },
            # {"CREATED" => lambda {|budget| format_local_dt(budget['dateCreated']) } },
            # {"UPDATED" => lambda {|budget| format_local_dt(budget['lastUpdated']) } },
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
          print_dry_run @budgets_interface.dry.get(args[0], params)
        else
          print_dry_run @budgets_interface.dry.list({name: args[0].to_s})
        end
        return 0
      end
      budget = find_budget_by_name_or_id(args[0])
      return 1 if budget.nil?
      # skip reload if already fetched via get(id)
      json_response = {'budget' => budget}
      if args[0].to_s != budget['id'].to_s
        json_response = @budgets_interface.get(budget['id'], params)
        budget = json_response['budget']
      end
      render_result = render_with_format(json_response, options, 'budget')
      return 0 if render_result

      
      print_h1 "Budget Details"
      print cyan
      budget_columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Enabled" => lambda {|budget| format_boolean(budget['enabled']) },
        "Scope" => lambda {|it| format_budget_scope(it) },
        "Period" => lambda {|it| it['year'] },
        "Interval" => lambda {|it| it['interval'].to_s.capitalize },
        # "Costs" => lambda {|it| it['costs'].inspect },
      }
      if budget['interval'] == 'year'
        budget_columns.merge!({
          "Annual" => lambda {|it| 
            (it['costs'] && it['costs']['year']) ? format_money(it['costs']['year'], it['currency']) : '' 
          },
        })
      elsif budget['interval'] == 'quarter'
        budget_columns.merge!({
          "Q1" => lambda {|it| (it['costs'] && it['costs']['q1']) ? format_money(it['costs']['q1'], it['currency']) : ''   },
          "Q2" => lambda {|it| (it['costs'] && it['costs']['q2']) ? format_money(it['costs']['q2'], it['currency']) : ''  },
          "Q3" => lambda {|it| (it['costs'] && it['costs']['q3']) ? format_money(it['costs']['q3'], it['currency']) : ''  },
          "Q4" => lambda {|it| (it['costs'] && it['costs']['q4']) ? format_money(it['costs']['q4'], it['currency']) : ''  },
        })
      elsif budget['interval'] == 'month'
        budget_columns.merge!({
          "January" => lambda {|it| (it['costs'] && it['costs']['january']) ? format_money(it['costs']['january'], it['currency']) : ''  },
          "February" => lambda {|it| (it['costs'] && it['costs']['february']) ? format_money(it['costs']['february'], it['currency']) : ''  },
          "March" => lambda {|it| (it['costs'] && it['costs']['march']) ? format_money(it['costs']['march'], it['currency']) : ''  },
          "April" => lambda {|it| (it['costs'] && it['costs']['april']) ? format_money(it['costs']['april'], it['currency']) : ''  },
          "May" => lambda {|it| (it['costs'] && it['costs']['may']) ? format_money(it['costs']['may'], it['currency']) : ''  },
          "June" => lambda {|it| (it['costs'] && it['costs']['june']) ? format_money(it['costs']['june'], it['currency']) : ''  },
          "July" => lambda {|it| (it['costs'] && it['costs']['july']) ? format_money(it['costs']['july'], it['currency']) : ''  },
          "August" => lambda {|it| (it['costs'] && it['costs']['august']) ? format_money(it['costs']['august'], it['currency']) : ''  },
          "September" => lambda {|it| (it['costs'] && it['costs']['september']) ? format_money(it['costs']['september'], it['currency']) : ''  },
          "October" => lambda {|it| (it['costs'] && it['costs']['october']) ? format_money(it['costs']['october'], it['currency']) : ''  },
          "November" => lambda {|it| (it['costs'] && it['costs']['november']) ? format_money(it['costs']['nov'], it['currency']) : ''  },
          "December" => lambda {|it| (it['costs'] && it['costs']['december']) ? format_money(it['costs']['december'], it['currency']) : ''  }
        })
      else
        budget_columns.merge!({
          "Costs" => lambda {|it| 
            if it['costs'].is_a?(Array)
              it['costs'] ? it['costs'].join(', ') : '' 
            elsif it['costs'].is_a?(Hash)
              it['costs'].to_s
            else
              it['costs'].to_s
            end
          },
        })
      end
      budget_columns.merge!({
        "Total" => lambda {|it| format_money(it['totalCost'], it['currency']) },
        "Average" => lambda {|it| format_money(it['averageCost'], it['currency']) },
        # the UI doesn't consider timezone, so uhh do it this hacky way for now.
        "Start Date" => lambda {|it| 
          if it['timezone'] == 'UTC'
            ((parse_time(it['startDate'], "%Y-%m-%d").strftime("%x")) rescue it['startDate']) # + ' UTC'
          else
            format_local_date(it['startDate']) 
          end
        },
        "End Date" => lambda {|it| 
          if it['timezone'] == 'UTC'
            ((parse_time(it['endDate'], "%Y-%m-%d").strftime("%x")) rescue it['endDate']) # + ' UTC'
          else
            format_local_date(it['endDate']) 
          end
        },
      })
      budget_columns.merge!({
        "Created By" => lambda {|it| it['createdByName'] ? it['createdByName'] : it['createdById'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      })
      print_description_list(budget_columns, budget, options)
      # print reset,"\n"

      # a chart of Budget cost vs Actual cost for each interval in the period.
      print_h2 "Budget Summary", options
      if budget['stats'] && budget['stats']['intervals']
        begin
          budget_summary_columns = {
            # "Cost" => lambda {|it| it[:label] },
            " " => lambda {|it| it[:label] },
          }
          budget_row = {label:"Budget"}
          actual_row = {label:"Actual"}
          # budget['stats']['intervals'].each do |stat_interval|
          #   interval_key = (stat_interval["shortName"] || stat_interval["shortYear"]).to_s.upcase
          #   if interval_key == "Y1" && budget['year']
          #     interval_key = "Year #{budget['year']}"
          #   end
          #   budget_summary_columns[interval_key] = lambda {|it| 
          #     display_val = format_money(it[interval_key], budget['stats']['currency'])
          #     over_budget = actual_row[interval_key] && (actual_row[interval_key] > (budget_row[interval_key] || 0))
          #     if over_budget
          #       "#{red}#{display_val}#{cyan}"
          #     else
          #       "#{cyan}#{display_val}#{cyan}"
          #     end
          #   }
          #   budget_row[interval_key] = stat_interval["budget"].to_f
          #   actual_row[interval_key] = stat_interval["cost"].to_f
          # end
          budget['stats']['intervals'].each do |stat_interval|
            currency = budget['currency'] || budget['stats']['currency']
            interval_key = (stat_interval["shortName"] || stat_interval["shortYear"]).to_s.upcase
            if interval_key == "Y1" && budget['year']
              interval_key = "Year #{budget['year']}"
            end
            # add simple column definition, just use the key
            budget_summary_columns[interval_key] = interval_key
            budget_cost = stat_interval["budget"].to_f
            actual_cost = stat_interval["cost"].to_f
            over_budget = actual_cost > 0 && actual_cost > budget_cost
            if over_budget
              budget_row[interval_key] = "#{cyan}#{format_money(budget_cost, currency)}#{cyan}"
              actual_row[interval_key] = "#{red}#{format_money(actual_cost, currency)}#{cyan}"
            else
              budget_row[interval_key] = "#{cyan}#{format_money(budget_cost, currency)}#{cyan}"
              actual_row[interval_key] = "#{cyan}#{format_money(actual_cost, currency)}#{cyan}"
            end
          end
          chart_data = [budget_row, actual_row]
          print as_pretty_table(chart_data, budget_summary_columns, options)
          print reset,"\n"
        rescue => ex
          print red,"Failed to render budget summary.",reset,"\n"
        end
      else
        print yellow,"No budget stat data found.",reset,"\n"
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
    costs = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_budget_option_types)
      opts.on('--cost [amount]', String, "Budget cost amount, for use with default year interval.") do |val|
        costs['year'] = (val.nil? || val.empty?) ? 0 : val.to_f
      end
      [:q1,:q2,:q3,:q4,
      ].each do |quarter|
        opts.on("--#{quarter.to_s} [amount]", String, "#{quarter.to_s.capitalize} cost amount, use with quarter interval.") do |val|
          costs[quarter.to_s] = parse_cost_amount(val)
        end
      end
      [:january,:february,:march,:april,:may,:june,:july,:august,:september,:october,:november,:december
      ].each do |month|
        opts.on("--#{month.to_s} [amount]", String, "#{month.to_s.capitalize} cost amount, use with month interval.") do |val|
          costs[month.to_s] = parse_cost_amount(val)
        end
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable a policy") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
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
        passed_options.delete('costs')
        passed_options.delete('tenant')
        passed_options.delete('group')
        passed_options.delete('cloud')
        passed_options.delete('user')
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
        # prompt for options
        if !costs.empty?
          options[:options]['costs'] ||= {}
          options[:options]['costs'].deep_merge!(costs)
        end
        options[:options]['interval'] = options[:options]['interval'].to_s.downcase if options[:options]['interval']
        v_prompt = Morpheus::Cli::OptionTypes.prompt(add_budget_option_types, options[:options], @api_client)
        params.deep_merge!(v_prompt)
        params['costs'] = prompt_costs(params, options)
        # budgets api expects scope prefixed parameters like this
        if params['tenant'].is_a?(String) || params['tenant'].is_a?(Numeric)
          params['scopeTenantId'] = params.delete('tenant')
        end
        if params['group'].is_a?(String) || params['group'].is_a?(Numeric)
          params['scopeGroupId'] = params.delete('group')
        end
        if params['cloud'].is_a?(String) || params['cloud'].is_a?(Numeric)
          params['scopeCloudId'] = params.delete('cloud')
        end
        if params['user'].is_a?(String) || params['user'].is_a?(Numeric)
          params['scopeUserId'] = params.delete('user')
        end
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
    params = {}
    costs = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[budget] [options]")
      build_option_type_options(opts, options, update_budget_option_types)
      opts.on('--cost [amount]', String, "Budget cost amount, for use with default year interval.") do |val|
        costs['year'] = (val.nil? || val.empty?) ? 0 : val.to_f
      end
      [:q1,:q2,:q3,:q4,
      ].each do |quarter|
        opts.on("--#{quarter.to_s} [amount]", String, "#{quarter.to_s.capitalize} cost amount, use with quarter interval.") do |val|
          costs[quarter.to_s] = parse_cost_amount(val)
        end
      end
      [:january,:february,:march,:april,:may,:june,:july,:august,:september,:october,:november,:december
      ].each do |month|
        opts.on("--#{month.to_s} [amount]", String, "#{month.to_s.capitalize} cost amount, use with month interval.") do |val|
          costs[month.to_s] = parse_cost_amount(val)
        end
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable a policy") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
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
        passed_options.delete('costs')
        passed_options.delete('tenant')
        passed_options.delete('group')
        passed_options.delete('cloud')
        passed_options.delete('user')
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_budget_option_types, options[:options], @api_client, options[:params])
        v_prompt = Morpheus::Cli::OptionTypes.prompt(update_budget_option_types, options[:options].merge(:no_prompt => true), @api_client)
        params.deep_merge!(v_prompt)
        # v_costs = prompt_costs({'interval' => budget['interval']}.merge(params), options.merge(:no_prompt => true))
        # if v_costs && !v_costs.empty?
        #   params['costs'] = v_costs
        # end
        if !costs.empty?
          params['costs'] = costs
        end
        # budgets api expects scope prefixed parameters like this
        if params['tenant'].is_a?(String) || params['tenant'].is_a?(Numeric)
          params['scopeTenantId'] = params.delete('tenant')
        end
        if params['group'].is_a?(String) || params['group'].is_a?(Numeric)
          params['scopeGroupId'] = params.delete('group')
        end
        if params['cloud'].is_a?(String) || params['cloud'].is_a?(Numeric)
          params['scopeCloudId'] = params.delete('cloud')
        end
        if params['user'].is_a?(String) || params['user'].is_a?(Numeric)
          params['scopeUserId'] = params.delete('user')
        end
        payload.deep_merge!({'budget' => params}) unless params.empty?

        if payload.empty? || payload['budget'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
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
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 1},
      # {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true},
      {'fieldName' => 'scope', 'fieldLabel' => 'Scope', 'code' => 'budget.scope', 'type' => 'select', 'selectOptions' => [{'name'=>'Account','value'=>'account'},{'name'=>'Tenant','value'=>'tenant'},{'name'=>'Cloud','value'=>'cloud'},{'name'=>'Group','value'=>'group'},{'name'=>'User','value'=>'user'}], 'defaultValue' => 'account', 'required' => true, 'displayOrder' => 3},
      {'fieldName' => 'tenant', 'fieldLabel' => 'Tenant', 'type' => 'select', 'optionSource' => lambda { 
        @options_interface.options_for_source("tenants", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:tenant', 'displayOrder' => 4},
      {'fieldName' => 'user', 'fieldLabel' => 'User', 'type' => 'select', 'optionSource' => lambda { 
        @options_interface.options_for_source("users", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:user', 'displayOrder' => 5},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'optionSource' => lambda { 
        @options_interface.options_for_source("groups", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:group', 'displayOrder' => 6},
      {'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'optionSource' => lambda { 
        @options_interface.options_for_source("clouds", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:cloud', 'displayOrder' => 7},
      {'fieldName' => 'year', 'fieldLabel' => 'Period', 'type' => 'text', 'required' => true, 'defaultValue' => Time.now.year, 'description' => "The period (year) the budget applies to. Default is the current year.", 'displayOrder' => 8},
      {'fieldName' => 'interval', 'fieldLabel' => 'Interval', 'type' => 'select', 'selectOptions' => [{'name'=>'Year','value'=>'year'},{'name'=>'Quarter','value'=>'quarter'},{'name'=>'Month','value'=>'month'}], 'defaultValue' => 'year', 'required' => true, 'displayOrder' => 9}
    ]
  end

  def update_budget_option_types
    list = add_budget_option_types()
    # list = list.reject {|it| ["interval"].include? it['fieldName'] }
    list.each {|it| it.delete('required') }
    list.each {|it| it.delete('defaultValue') }
    list
  end

  def prompt_costs(params={}, options={})
    interval = params['interval'] #.to_s.downcase
    options[:options]||={}
    costs = {}
    costs_val = nil
    #costs_val = params['costs'] ? params['costs'] : options[:options]['costs']
    if costs_val.is_a?(Array)
      costs = costs_val
    elsif costs_val.is_a?(String)
      costs = costs_val.to_s.split(',').collect {|it| it.to_s.strip.to_f }
    else
      if interval == 'year'
        cost_option_types = [
          {'fieldContext' => 'costs', 'fieldName' => 'year', 'fieldLabel' => 'Annual Cost', 'type' => 'text', 'defaultValue' => 0}
        ]
        values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
        costs = values['costs'] ? values['costs'] : {}
        # costs = {
        #   year: values['cost']
        # }
      elsif interval == 'quarter'
        cost_option_types = [
          {'fieldContext' => 'costs', 'fieldName' => 'q1', 'fieldLabel' => 'Q1', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 1},
          {'fieldContext' => 'costs', 'fieldName' => 'q2', 'fieldLabel' => 'Q2', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 2},
          {'fieldContext' => 'costs', 'fieldName' => 'q3', 'fieldLabel' => 'Q3', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 3},
          {'fieldContext' => 'costs', 'fieldName' => 'q4', 'fieldLabel' => 'Q4', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 4}
        ]
        values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
        costs = values['costs'] ? values['costs'] : {}
        # costs = {
        #   q1: values['q1'], q2: values['q2'], q3: values['q3'], q4: values['q4']
        # }
      elsif interval == 'month'
        cost_option_types = [
          {'fieldContext' => 'costs', 'fieldName' => 'january', 'fieldLabel' => 'January', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 1},
          {'fieldContext' => 'costs', 'fieldName' => 'february', 'fieldLabel' => 'February', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 2},
          {'fieldContext' => 'costs', 'fieldName' => 'march', 'fieldLabel' => 'March', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 3},
          {'fieldContext' => 'costs', 'fieldName' => 'april', 'fieldLabel' => 'April', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 4},
          {'fieldContext' => 'costs', 'fieldName' => 'may', 'fieldLabel' => 'May', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 5},
          {'fieldContext' => 'costs', 'fieldName' => 'june', 'fieldLabel' => 'June', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 6},
          {'fieldContext' => 'costs', 'fieldName' => 'july', 'fieldLabel' => 'July', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 7},
          {'fieldContext' => 'costs', 'fieldName' => 'august', 'fieldLabel' => 'August', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 8},
          {'fieldContext' => 'costs', 'fieldName' => 'september', 'fieldLabel' => 'September', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 9},
          {'fieldContext' => 'costs', 'fieldName' => 'october', 'fieldLabel' => 'October', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 10},
          {'fieldContext' => 'costs', 'fieldName' => 'november', 'fieldLabel' => 'November', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 11},
          {'fieldContext' => 'costs', 'fieldName' => 'december', 'fieldLabel' => 'December', 'type' => 'text', 'defaultValue' => 0, 'displayOrder' => 12},
        ]
        values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
        costs = values['costs'] ? values['costs'] : {}
        # costs = {
        #   january: values['january'], february: values['february'], march: values['march'],
        #   april: values['april'], may: values['may'], june: values['june'],
        #   july: values['july'], august: values['august'], september: values['september'],
        #   october: values['october'], november: values['november'], december: values['december']
        # }
      end
    end
    return costs
  end

  def format_budget_scope(budget)
    if budget['refScope'] && budget['refName']
      "(#{budget['refScope']}) #{budget['refName']}"
    elsif budget['refType']
      budget['refType'] ? "#{budget['refType']} (#{budget['refId']}) #{budget['refName']}".strip : budget['refName'].to_s
    else
      ""
    end
  end

  def parse_cost_amount(val)
    val.to_s.gsub(",","").to_f
  end

end
