require 'morpheus/cli/cli_command'

# CLI command for the Service Catalog (Persona): Dashboard / Catalog / Inventory
# Inventory Items are the main actions, list, get, remove
# The add command adds to the cart and checkout places an order with the cart.
# The add-order command allows submitting a new order at once.
class Morpheus::Cli::CatalogCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper

  # set_command_name :'service-catalog'
  set_command_name :'catalog'
  set_command_description "Service Catalog Persona: View catalog and manage inventory"

  # dashboard
  register_subcommands :dashboard
  # catalog (catalogItemTypes)
  register_subcommands :'list-types' => :list_types
  register_subcommands :'get-type' => :get_type
  alias_subcommand :types, :'list-types'
  
  # inventory (items) IS the main crud here
  register_subcommands :list, :get, :remove

  # cart / orders
  register_subcommands :cart => :get_cart
  register_subcommands :'update-cart' => :update_cart
  register_subcommands :add
  #register_subcommands :'update-cart-item' => :update_cart_item
  register_subcommands :'remove-cart-item' => :remove_cart_item
  register_subcommands :'clear-cart' => :clear_cart
  register_subcommands :checkout

  # create and submit cart in one action
  # maybe call this place-order instead?
  register_subcommands :'add-order' => :add_order

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @service_catalog_interface = @api_client.catalog
    # @instances_interface = @api_client.instances
    @option_types_interface = @api_client.option_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def dashboard(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View service catalog dashboard.
Provides an overview of available catalog item types, recent orders and inventory.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:0)
    connect(options)
  
    params.merge!(parse_list_options(options))
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.dashboard(params)
      return
    end
    json_response = @service_catalog_interface.dashboard(params)
    catalog_item_types = json_response['catalogItemTypes']
    catalog_meta = json_response['catalogMeta'] || {}
    recent_items = json_response['recentItems'] || {}
    featured_items = json_response['featuredItems'] || []
    inventory_items = json_response['inventoryItems'] || []
    inventory_meta = json_response['inventoryMeta'] || {}
    cart = json_response['cart'] || {}
    cart_items = cart['items'] || []
    cart_stats = cart['stats'] || {}
    current_invoice = json_response['currentInvoice']
    
    render_response(json_response, options, catalog_item_type_object_key) do
      print_h1 "Catalog Dashboard", [], options
      print cyan
      
      # dashboard_columns = [
      #   {"TYPES" => lambda {|it| catalog_meta['total'] } },
      #   {"INVENTORY" => lambda {|it| inventory_items.size rescue '' } },
      #   {"CART" => lambda {|it| it['cart']['items'].size rescue '' } },
      # ]
      # print as_pretty_table([json_response], dashboard_columns, options)

      print_h2 "Catalog Items"
      print as_pretty_table(catalog_item_types, {
        "NAME" => lambda {|it| it['name'] },
        "DESCRIPTION" => lambda {|it| it['description'] },
        "FEATURED" => lambda {|it| format_boolean it['featured'] },
      }, options)
      # print reset,"\n"

      if recent_items && recent_items.size() > 0
        print_h2 "Recently Ordered"
        print as_pretty_table(recent_items, {
          #"ID" => lambda {|it| it['id'] },
          #"NAME" => lambda {|it| it['name'] },
          "TYPE" => lambda {|it| it['type']['name'] rescue '' },
          #"QTY" => lambda {|it| it['quantity'] },
          "ORDER DATE" => lambda {|it| format_local_dt(it['orderDate']) },
          # "STATUS" => lambda {|it| format_catalog_item_status(it) },
          # "CONFIG" => lambda {|it| truncate_string(format_name_values(it['config']), 50) },
        }, options)
        # print reset,"\n"
      end

      if recent_items && recent_items.size() > 0
        print_h2 "Inventory"
        print as_pretty_table(inventory_items, {
          "ID" => lambda {|it| it['id'] },
          "NAME" => lambda {|it| it['name'] },
          "TYPE" => lambda {|it| it['type']['name'] rescue '' },
          #"QTY" => lambda {|it| it['quantity'] },
          "ORDER DATE" => lambda {|it| format_local_dt(it['orderDate']) },
          "STATUS" => lambda {|it| format_catalog_item_status(it) },
          # "CONFIG" => lambda {|it| format_name_values(it['config']) },
        }, options)
        print_results_pagination(inventory_meta)
      else
        # print_h2 "Inventory"
        # print cyan, "Inventory is empty", reset, "\n"
      end
      
      # print reset,"\n"

      # problematic right now, invoice has all user activity, not just catalog
      show_invoice = false
      if current_invoice && show_invoice
        print_h2 "Current Invoice"
        print cyan
        invoice_columns = {
          # todo: invoice needs to return a currency!!!
          "Compute" => lambda {|it| format_money(it['computePrice'], cart_stats['currency']) },
          "Storage" => lambda {|it| format_money(it['storagePrice'], cart_stats['currency']) },
          "Memory" => lambda {|it| format_money(it['memoryPrice'], cart_stats['currency']) },
          "Network" => lambda {|it| format_money(it['networkPrice'], cart_stats['currency']) },
          "Extra" => lambda {|it| format_money(it['extraPrice'], cart_stats['currency']) },
          "MTD" => lambda {|it| format_money(it['runningPrice'], cart_stats['currency']) },
          "Total (Projected)" => lambda {|it| format_money(it['totalPrice'], cart_stats['currency']) },
          #"Items" => lambda {|it| cart['items'].size },
          # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        }
        invoice_columns.delete("Storage") unless current_invoice['storagePrice'] && current_invoice['storagePrice'].to_f > 0
        invoice_columns.delete("Memory") unless current_invoice['memoryPrice'] && current_invoice['memoryPrice'].to_f > 0
        invoice_columns.delete("Network") unless current_invoice['networkPrice'] && current_invoice['networkPrice'].to_f > 0
        invoice_columns.delete("Extra") unless current_invoice['extraPrice'] && current_invoice['extraPrice'].to_f > 0
        print as_pretty_table(current_invoice, invoice_columns.upcase_keys!, options)
      end

      show_cart = false
      if show_cart
        if cart
          
          # get_cart([] + (options[:remote] ? ["-r",options[:remote]] : []))
          
          print_h2 "Cart"
          print cyan
          if cart['items'].size() > 0
            # cart_columns = {
            #   "Qty" => lambda {|it| cart['items'].sum {|cart_item| cart_item['quantity'] } },
            #   "Total" => lambda {|it| 
            #     begin
            #       format_money(cart_stats['price'], cart_stats['currency']) + (cart_stats['unit'].to_s.empty? ? "" : " / #{cart_stats['unit']}")
            #     rescue => ex
            #       raise ex
            #       # no cart stats eh?
            #     end
            #   },
            # }
            # print as_pretty_table(cart, cart_columns.upcase_keys!, options)


            cart_item_columns = [
              {"ID" => lambda {|it| it['id'] } },
              #{"NAME" => lambda {|it| it['name'] } },
              {"TYPE" => lambda {|it| it['type']['name'] rescue '' } },
              #{"QTY" => lambda {|it| it['quantity'] } },
              {"PRICE" => lambda {|it| format_money(it['price'] , it['currency'] || cart_stats['currency']) } },
              {"STATUS" => lambda {|it| 
                status_string = format_catalog_item_status(it)
                if it['errorMessage'].to_s != ""
                  status_string << " - #{it['errorMessage']}"
                end
                status_string
              } },
              # {"CONFIG" => lambda {|it| 
              #   truncate_string(format_name_values(it['config']), 50)
              # } },
            ]
            print as_pretty_table(cart_items, cart_item_columns)
          
            print reset,"\n"
            print cyan
            puts "Total: " + format_money(cart_stats['price'], cart_stats['currency']) + " / #{cart_stats['unit']}"
            # print reset,"\n"

          else
            print cyan, "Cart is empty", reset, "\n"
          end
        end
        
      end
      
      print reset,"\n"

    end
    return 0, nil
  end

  def list_types(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on( '--featured [on|off]', String, "Filter by featured" ) do |val|
        params['featured'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      build_standard_list_options(opts, options)
      opts.footer = "List available catalog item types."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.list_types(params)
      return
    end
    json_response = @service_catalog_interface.list_types(params)
    catalog_item_types = json_response[catalog_item_type_list_key]
    render_response(json_response, options, catalog_item_type_list_key) do
      print_h1 "Morpheus Catalog Types", parse_list_subtitles(options), options
      if catalog_item_types.empty?
        print cyan,"No catalog item types found.",reset,"\n"
      else
        list_columns = catalog_item_type_column_definitions.upcase_keys!
        #list_columns["Config"] = lambda {|it| truncate_string(it['config'], 100) }
        print as_pretty_table(catalog_item_types, list_columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if catalog_item_types.empty?
      return 1, "no catalog item types found"
    else
      return 0, nil
    end
  end
  
  def get_type(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific catalog item type.
[name] is required. This is the name or id of a catalog item type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get_type(arg, params, options)
    end
  end

  def _get_type(id, params, options)
    catalog_item_type = nil
    if id.to_s !~ /\A\d{1,}\Z/
      catalog_item_type = find_catalog_item_type_by_name(id)
      return 1, "catalog item type not found for #{id}" if catalog_item_type.nil?
      id = catalog_item_type['id']
    end
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.get_type(id, params)
      return
    end
    json_response = @service_catalog_interface.get_type(id, params)
    catalog_item_type = json_response[catalog_item_type_object_key]
    # need to load by id to get optionTypes
    # maybe do ?name=foo&includeOptionTypes=true 
    if catalog_item_type['optionTypes'].nil?
      catalog_item_type = find_catalog_item_type_by_id(catalog_item_type['id'])
      return [1, "catalog item type not found"] if catalog_item_type.nil?
    end
    render_response(json_response, options, catalog_item_type_object_key) do
      print_h1 "Catalog Type Details", [], options
      print cyan
      show_columns = catalog_item_type_column_definitions
      print_description_list(show_columns, catalog_item_type)

      if catalog_item_type['optionTypes'] && catalog_item_type['optionTypes'].size > 0
        print_h2 "Configuration Options"
        print as_pretty_table(catalog_item_type['optionTypes'], {
          "LABEL" => lambda {|it| it['fieldLabel'] },
          "NAME" => lambda {|it| it['fieldName'] },
          "TYPE" => lambda {|it| it['type'] },
          "REQUIRED" => lambda {|it| format_boolean it['required'] },
        })
      else
        # print cyan,"No option types found for this catalog item.","\n",reset
      end

      print reset,"\n"
    end
    return 0, nil
  end

  # inventory actions

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on('-t', '--type TYPE', String, "Catalog Item Type Name or ID") do |val|
        type_id = val.to_s
      end
      build_standard_list_options(opts, options)
      opts.footer = "List catalog inventory."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.list_inventory(params)
      return
    end
    json_response = @service_catalog_interface.list_inventory(params)
    catalog_items = json_response[catalog_item_list_key]
    render_response(json_response, options, catalog_item_list_key) do
      print_h1 "Morpheus Catalog Inventory", parse_list_subtitles(options), options
      if catalog_items.empty?
        print cyan,"No catalog items found.",reset,"\n"
      else
        list_columns = catalog_item_column_definitions.upcase_keys!
        #list_columns["Config"] = lambda {|it| truncate_string(it['config'], 100) }
        print as_pretty_table(catalog_items, list_columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if catalog_items.empty?
      return 1, "no catalog items found"
    else
      return 0, nil
    end
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on( '-c', '--config', "Display raw config only. Default is YAML. Combine with -j for JSON instead." ) do
        options[:show_config] = true
      end
      # opts.on('--no-config', "Do not display config content." ) do
      #   options[:no_config] = true
      # end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific catalog inventory item.
[id] is required. This is the id of a catalog inventory item.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    catalog_item = nil
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.get_inventory(id, params)
      return
    end
    #json_response = @service_catalog_interface.get_inventory(id, params)
    catalog_item = find_catalog_item_by_id(id)
    return 1, "catalog item not found for id #{id}" if catalog_item.nil?
    json_response = {catalog_item_object_key => catalog_item}

    catalog_item = json_response[catalog_item_object_key]
    item_config = catalog_item['config']
    item_type_code = catalog_item['type']['type'] rescue nil
    item_instance = catalog_item['instance']
    item_app = catalog_item['app']
    item_execution = catalog_item['execution']
    render_response(json_response, options, catalog_item_object_key) do
      print_h1 "Catalog Item Details", [], options
      print cyan
      show_columns = catalog_item_column_definitions
      # show_columns.delete("Status") if catalog_item['status'].to_s.lowercase == 'ORDERED'
      show_columns.delete("Status") if item_instance || item_app
      print_description_list(show_columns, catalog_item)

      if item_config && !item_config.empty?
        # print_h2 "Configuration", options
        # print cyan
        # print as_description_list(item_config, item_config.keys, options)
        # print "\n", reset
      end

      if item_type_code.to_s.downcase == 'instance'
        if item_instance
          print_h2 "Instance", options
          print cyan
          item_instance_columns = [
              {"ID" => lambda {|it| it['id'] } },
              {"NAME" => lambda {|it| it['name'] } },
              {"STATUS" => lambda {|it| format_instance_status(it) } },
            ]
            #print as_description_list(item_instance, item_instance_columns, options)
            print as_pretty_table([item_instance], item_instance_columns, options)
          # print "\n", reset
        else
          print "\n"
          print yellow, "No instance found", reset, "\n"
        end
      end

      if item_type_code.to_s.downcase == 'app'
        if item_instance
          print_h2 "App", options
          print cyan
          item_app_columns = [
              {"ID" => lambda {|it| it['id'] } },
              {"NAME" => lambda {|it| it['name'] } },
              {"STATUS" => lambda {|it| format_app_status(it) } },
            ]
            #print as_description_list(item_app, item_app_columns, options)
            print as_pretty_table([item_app], item_app_columns, options)
          # print "\n", reset
        else
          print "\n"
          print yellow, "No instance found", reset, "\n"
        end
      end

      print reset,"\n"
    end
    return 0, nil
  end

  def get_cart(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-a', '--details', "Display all details: item configuration." ) do
        options[:details] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details of current cart and the items in it.
Exits non-zero if cart is empty.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.get_cart(params)
      return 0, nil
    end
    # skip extra query, list has same data as show right now
    json_response = @service_catalog_interface.get_cart(params)
    cart = json_response['cart']
    cart_items = cart['items'] || []
    cart_stats = cart['stats'] || {}
    render_response(json_response, options, 'cart') do
      print_h1 "Catalog Cart", [], options
      print_order_details(cart, options)
    end
    if cart_items.empty?
      return 1, "cart is empty"
    else
      return 0, nil
    end
  end

  def update_cart(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--name [name]")
      opts.on('--name [NAME]', String, "Set an optional name for your catalog order") do |val|
        options[:options]['name'] = val.to_s
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update your cart settings, such as name.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    # fetch current cart
    # cart = @service_catalog_interface.get_cart()['cart']
    payload = {}
    update_cart_object_key = 'order'
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({update_cart_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({update_cart_object_key => parse_passed_options(options)})
      payload.deep_merge!({update_cart_object_key => params})
      if payload[update_cart_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.update_cart(payload)
      return
    end
    json_response = @service_catalog_interface.update_cart(payload)
    #cart = json_response['cart']
    #cart = @service_catalog_interface.get_cart()['cart']
    render_response(json_response, options, 'cart') do
      print_green_success "Updated cart"
      get_cart([] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    payload = {}
    type_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type] [options]")
      opts.on('-t', '--type TYPE', String, "Catalog Item Type Name or ID") do |val|
        type_id = val.to_s
      end
      opts.on('--validate','--validate', "Validate Only. Validates the configuration and skips adding the item.") do
        options[:validate_only] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Add an item to your cart
[type] is required, this is name or id of a catalog item type.
Catalog item types may require additional configuration.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0)
    connect(options)
    if args.count > 0
      type_id = args.join(" ")
    end
    payload = {}
    add_item_object_key = 'item'
    payload = {add_item_object_key => {} }
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({add_item_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({add_item_object_key => parse_passed_options(options)})
      # prompt for Type
      if type_id
        catalog_item_type = find_catalog_item_type_by_name_or_id(type_id)
        return [1, "catalog item type not found"] if catalog_item_type.nil?
      elsif
        catalog_type_option_type = {'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
          # @options_interface.options_for_source("licenseTypes", {})['data']
          @service_catalog_interface.list_types({max:10000})['catalogItemTypes'].collect {|it|
            {'name' => it['name'], 'value' => it['id']}
          } }, 'required' => true, 'description' => 'Catalog Item Type name or id'}
        type_id = Morpheus::Cli::OptionTypes.prompt([catalog_type_option_type], options[:options], @api_client, options[:params])['type']
        catalog_item_type = find_catalog_item_type_by_name_or_id(type_id.to_s)
        return [1, "catalog item type not found"] if catalog_item_type.nil?
      end
      # use name instead of id
      payload[add_item_object_key]['type'] = {'name' => catalog_item_type['name']}
      #payload[add_item_object_key]['type'] = {'id' => catalog_item_type['id']}

      # this is silly, need to load by id to get optionTypes
      # maybe do ?name=foo&includeOptionTypes=true 
      if catalog_item_type['optionTypes'].nil?
        catalog_item_type = find_catalog_item_type_by_id(catalog_item_type['id'])
        return [1, "catalog item type not found"] if catalog_item_type.nil?
      end
      catalog_option_types = catalog_item_type['optionTypes']
      # instead of config.customOptions just use config...
      catalog_option_types = catalog_option_types.collect {|it|
        it['fieldContext'] = 'config'
        it
      }
      if catalog_option_types && !catalog_option_types.empty?
        config_prompt = Morpheus::Cli::OptionTypes.prompt(catalog_option_types, options[:options], @api_client, {})['config']
        payload[add_item_object_key].deep_merge!({'config' => config_prompt})
      end
    end
    if options[:validate_only]
      params['validateOnly'] = true
    end
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.create_cart_item(payload, params)
      return
    end
    json_response = @service_catalog_interface.create_cart_item(payload, params)
    cart_item = json_response['item']
    render_response(json_response, options) do
      if options[:validate_only]
        if json_response['success']
          print_green_success(json_response['msg'] || "Item is valid")
          print_h2 "Validated Cart Item", [], options
          cart_item_columns = {
            "Type" => lambda {|it| it['type']['name'] rescue '' },
            #"Qty" => lambda {|it| it['quantity'] },
            "Price" => lambda {|it| format_money(it['price'] , it['currency']) },
            #"Config" => lambda {|it| truncate_string(format_name_values(it['config']), 50) }
          }
          print as_pretty_table([cart_item], cart_item_columns.upcase_keys!)
          print reset, "\n"
        else
          # not needed because it will be http 400
          print_rest_errors(json_response, options)
        end
      else
        print_green_success "Added item to cart"
        get_cart([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    end
    if json_response['success']
      return 0, nil
    else
      # not needed because it will be http 400
      return 1, json_response['msg'] || 'request failed'
    end
  end

  def update_cart_item(args)
    #todo
    raise_command_error "Not yet implemented"
  end

  def remove_cart_item(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an item from the cart.
[id] is required. This is the id of a cart item (also matches on type)
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    connect(options)
    
    # fetch current cart
    cart = @service_catalog_interface.get_cart()['cart']
    cart_items = cart['items'] || []
    cart_item = nil
    item_id = args[0]
    # match cart item on id OR type.name
    if item_id.nil?
      cart_item_option_type = {'fieldName' => 'id', 'fieldLabel' => 'Cart Item', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
          # cart_items.collect {|ci| {'name' => ci['name'], 'value' => ci['id']} }
          cart_items.collect {|ci| {'name' => (ci['type']['name'] rescue ci['name']), 'value' => ci['id']} }
        }, 'required' => true, 'description' => 'Cart Item to be removed'}
      item_id = Morpheus::Cli::OptionTypes.prompt([cart_item_option_type], options[:options], @api_client)['id']
    end
    if item_id
      cart_item = cart_items.find { |ci| ci['id'] == item_id.to_i }
      if cart_item.nil?
        matching_items = cart_items.select { |ci| (ci['type']['name'] rescue nil) == item_id.to_s }
        if matching_items.size > 1
          print_red_alert "#{matching_items.size} cart items matched '#{item_id}'"
          cart_item_columns = [
              {"ID" => lambda {|it| it['id'] } },
              #{"NAME" => lambda {|it| it['name'] } },
              {"Type" => lambda {|it| it['type']['name'] rescue '' } },
              #{"Qty" => lambda {|it| it['quantity'] } },
              {"Price" => lambda {|it| format_money(it['price'] , it['currency']) } },
            ]
          puts_error as_pretty_table(matching_items, cart_item_columns, {color:red})
          print_red_alert "Try using ID instead"
          print reset,"\n"
          return nil
        end
        cart_item = matching_items[0]
      end
    end
    if cart_item.nil?
      err = "Cart item not found for '#{item_id}'"
      print_red_alert err
      return 1, err
    end

    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.destroy_cart_item(cart_item['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to remove item '#{cart_item['type']['name'] rescue cart_item['id']}' from your cart?")
      return 9, "aborted command"
    end
    json_response = @service_catalog_interface.destroy_cart_item(cart_item['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed item from cart"
      get_cart([] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def clear_cart(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--name [name]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Clear your cart.
This will empty the cart, deleting all items.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    # fetch current cart
    # cart = @service_catalog_interfaceg.get_cart()['cart']
    params.merge!(parse_query_options(options))
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.clear_cart(params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to clear your cart?")
      return 9, "aborted command"
    end
    json_response = @service_catalog_interface.clear_cart(params)
    render_response(json_response, options, 'cart') do
      print_green_success "Cleared cart"
      get_cart([] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def checkout(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--name [name]")
      # opts.on('--name [NAME]', String, "Set an optional name for your catalog order") do |val|
      #   options[:options]['name'] = val.to_s
      # end
      build_standard_add_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Checkout to complete your cart and place an order.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    # fetch current cart
    # cart = @service_catalog_interface.get_cart()['cart']
    params.merge!(parse_query_options(options))
    payload = {}
    if options[:payload]
      payload = options[:payload]
    end
    update_cart_object_key = 'order'
    passed_options = parse_passed_options(options)
    payload.deep_merge!({update_cart_object_key => passed_options}) unless passed_options.empty?
    
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.checkout(payload)
      return
    end

    # checkout
    print_h1 "Checkout"

    # review cart
    # should load this first, but do this to avoid double load
    cmd_result, cmd_err = get_cart(["--thin"] + (options[:remote] ? ["-r",options[:remote]] : []))
    if cmd_result != 0
      print_red_alert "You must add items before you can checkout. Try `catalog add`"
      return cmd_result, cmd_err
    end
        
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to checkout and place an order?")
      return 9, "aborted command"
    end
    json_response = @service_catalog_interface.checkout(payload, params)
    render_response(json_response, options) do
      print_green_success "Order placed"
      # ok so this is delayed because list does not return all statuses right now..
      #list([] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def add_order(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--validate','--validate', "Validate Only. Validates the configuration and skips creating the order.") do
        options[:validate_only] = true
      end
      opts.on('-a', '--details', "Display all details: item configuration." ) do
        options[:details] = true
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Place an order for new inventory.
This allows creating a new order without using the cart.
The order must contain one or more items, each with a valid type and configuration.
By default the order is placed right away.
Use the --validate option to validate and review the order without actually placing it.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0)
    connect(options)
    if args.count > 0
      type_id = args.join(" ")
    end
    payload = {}
    order_object_key = 'order'
    payload = {order_object_key => {} }
    passed_options = parse_passed_options(options)
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({order_object_key => passed_options}) unless passed_options.empty?
    else
      payload.deep_merge!({order_object_key => passed_options}) unless passed_options.empty?

      # Prompt for 1-N Types
      still_prompting = options[:no_prompt] != true
      available_catalog_item_types = @service_catalog_interface.list_types({max:10000})['catalogItemTypes'].collect {|it|
        {'name' => it['name'], 'value' => it['id']}
      }
      type_cache = {} # prevent repeat lookups
      while still_prompting do
        item_payload = {}
        # prompt for Type
        type_id = nil
        if type_id
          catalog_item_type = type_cache[type_id.to_s] || find_catalog_item_type_by_name_or_id(type_id)
          return [1, "catalog item type not found"] if catalog_item_type.nil?
        elsif
          type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => available_catalog_item_types, 'required' => true, 'description' => 'Catalog Item Type name or id'}], options[:options], @api_client, options[:params])['type']
          catalog_item_type = type_cache[type_id.to_s] || find_catalog_item_type_by_name_or_id(type_id.to_s)
          return [1, "catalog item type not found"] if catalog_item_type.nil?
        end
        type_cache[type_id.to_s] = catalog_item_type
        # use name instead of id
        item_payload['type'] = {'name' => catalog_item_type['name']}
        #payload[add_item_object_key]['type'] = {'id' => catalog_item_type['id']}

        # this is silly, need to load by id to get optionTypes
        # maybe do ?name=foo&includeOptionTypes=true 
        if catalog_item_type['optionTypes'].nil?
          catalog_item_type = find_catalog_item_type_by_id(catalog_item_type['id'])
          return [1, "catalog item type not found"] if catalog_item_type.nil?
        end
        catalog_option_types = catalog_item_type['optionTypes']
        # instead of config.customOptions just use config...
        catalog_option_types = catalog_option_types.collect {|it|
          it['fieldContext'] = 'config'
          it
        }
        if catalog_option_types && !catalog_option_types.empty?
          config_prompt = Morpheus::Cli::OptionTypes.prompt(catalog_option_types, options[:options], @api_client, {})['config']
          item_payload.deep_merge!({'config' => config_prompt})
        end
        
        payload[order_object_key]['items'] ||= []
        payload[order_object_key]['items'] << item_payload

        still_prompting =  Morpheus::Cli::OptionTypes.confirm("Add another item?")
      end
      
      
    end
    if options[:validate_only]
      params['validateOnly'] = true
      #payload['validateOnly'] = true
    end
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.create_order(payload, params)
      return
    end
    json_response = @service_catalog_interface.create_order(payload, params)
    order = json_response['order'] || json_response['cart']
    render_response(json_response, options) do
      if options[:validate_only]
        if json_response['success']
          print_green_success(json_response['msg'] || "Order is valid")
          print_h2 "Review Order", [], options
          print_order_details(order, options)
        else
          # not needed because it will be http 400
          print_rest_errors(json_response, options)
        end
      else
        print_green_success "Order placed"
        print_h2 "Order Details", [], options
        print_order_details(order, options)
      end
    end
    if json_response['success']
      return 0, nil
    else
      # not needed because it will be http 400
      return 1, json_response['msg'] || 'request failed'
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      opts.on('--remove-instances [true|false]', String, "Remove instances. Default is true. Applies to apps only.") do |val|
        params[:removeInstances] = ['true','on','1',''].include?(val.to_s.downcase)
      end
      opts.on( '-B', '--keep-backups [true|false]', "Preserve copy of backups. Default is false." ) do
        params[:keepBackups] = ['true','on','1',''].include?(val.to_s.downcase)
      end
      opts.on('--preserve-volumes [on|off]', String, "Preserve Volumes. Default is off. Applies to certain types only.") do |val|
        params[:preserveVolumes] = ['true','on','1',''].include?(val.to_s.downcase)
      end
      opts.on('--releaseEIPs [true|false]', String, "Release EIPs. Default is on. Applies to Amazon only.") do |val|
        params[:releaseEIPs] = ['true','on','1',''].include?(val.to_s.downcase)
      end
      opts.on( '-f', '--force', "Force Delete" ) do
        params[:force] = true
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a catalog inventory item.
This removes the item from the inventory and deprovisions the associated instance(s).
[id] is required. This is the id of a catalog inventory item.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    catalog_item = find_catalog_item_by_id(args[0])
    return 1 if catalog_item.nil?
    
    is_app = (catalog_item['type']['type'] == 'app' || catalog_item['type']['type'] == 'blueprint') rescue false
    
    params.merge!(parse_query_options(options))
    # delete dialog
    # we do not have provisioning settings right now to know if we can prompt for volumes / eips
    # skip force because it is excessive prompting...
    delete_prompt_options = [
      {'fieldName' => 'removeInstances', 'fieldLabel' => 'Remove Instances', 'type' => 'checkbox', 'defaultValue' => true},
      {'fieldName' => 'keepBackups', 'fieldLabel' => 'Preserve Backups', 'type' => 'checkbox', 'defaultValue' => false},
      #{'fieldName' => 'preserveVolumes', 'fieldLabel' => 'Preserve Volumes', 'type' => 'checkbox', 'defaultValue' => false},
      # {'fieldName' => 'releaseEIPs', 'fieldLabel' => 'Release EIPs. Default is on. Applies to Amazon only.', 'type' => 'checkbox', 'defaultValue' => true},
      #{'fieldName' => 'force', 'fieldLabel' => 'Force Delete', 'type' => 'checkbox', 'defaultValue' => false},
    ]
    if !is_app
      delete_prompt_options.reject! {|it| it['fieldName'] == 'removeInstances'}
    end
    options[:options][:no_prompt] = true if options[:yes] # -y could always mean do not prompt too..
    v_prompt = Morpheus::Cli::OptionTypes.prompt(delete_prompt_options, options[:options], @api_client)
    v_prompt.booleanize! # 'on' => true
    params.deep_merge!(v_prompt)

    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the inventory item #{catalog_item['id']} '#{catalog_item['name']}'?")
      return 9, "aborted command"
    end
    @service_catalog_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_catalog_interface.dry.destroy_inventory(catalog_item['id'], params)
      return
    end
    json_response = @service_catalog_interface.destroy_inventory(catalog_item['id'], params)
    render_response(json_response, options) do
      print_green_success "Removing catalog item"
    end
    return 0, nil
  end

  private

  # Catalog Item Types helpers

  def catalog_item_type_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      # "Type" => lambda {|it| format_catalog_type(it) },
      # "Blueprint" => lambda {|it| it['blueprint'] ? it['blueprint']['name'] : nil },
      # "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Featured" => lambda {|it| format_boolean(it['featured']) },
      #"Config" => lambda {|it| it['config'] },
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def catalog_item_type_object_key
    'catalogItemType'
  end

  def catalog_item_type_list_key
    'catalogItemTypes'
  end

  def find_catalog_item_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_catalog_item_type_by_id(val)
    else
      return find_catalog_item_type_by_name(val)
    end
  end

  # this returns optionTypes and list does not..
  def find_catalog_item_type_by_id(id)
    begin
      json_response = @service_catalog_interface.get_type(id.to_i)
      return json_response[catalog_item_type_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Catalog item type not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_catalog_item_type_by_name(name)
    json_response = @service_catalog_interface.list_types({name: name.to_s})
    catalog_item_types = json_response[catalog_item_type_list_key]
    if catalog_item_types.empty?
      print_red_alert "Catalog item type not found by name '#{name}'"
      return nil
    elsif catalog_item_types.size > 1
      print_red_alert "#{catalog_item_types.size} catalog item types found by name '#{name}'"
      puts_error as_pretty_table(catalog_item_types, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return catalog_item_types[0]
    end
  end

  def catalog_item_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      #"Description" => 'description',
      "Type" => lambda {|it| it['type']['name'] rescue '' },
      #"Qty" => lambda {|it| it['quantity'] },
      # "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      "Order Date" => lambda {|it| format_local_dt(it['orderDate']) },
      "Status" => lambda {|it| format_catalog_item_status(it) },
      # "Config" => lambda {|it| format_name_values(it['config']) },
    }
  end

  # Catalog Items (Inventory) helpers

  def catalog_item_object_key
    'item'
  end

  def catalog_item_list_key
    'items'
  end

  def find_catalog_item_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_catalog_item_by_id(val)
    else
      return find_catalog_item_by_name(val)
    end
  end

  def find_catalog_item_by_id(id)
    begin
      json_response = @service_catalog_interface.get_inventory(id.to_i)
      return json_response[catalog_item_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Catalog item not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  # find by name not yet supported, items do not have a name
  # def find_catalog_item_by_name(name)
  #   json_response = @service_catalog_interface.list_inventory({name: name.to_s})
  #   catalog_items = json_response[catalog_item_list_key]
  #   if catalog_items.empty?
  #     print_red_alert "Catalog item type not found by name '#{name}'"
  #     return nil
  #   elsif catalog_items.size > 1
  #     print_red_alert "#{catalog_items.size} catalog items found by name '#{name}'"
  #     puts_error as_pretty_table(catalog_items, [:id, :name], {color:red})
  #     print_red_alert "Try using ID instead"
  #     print reset,"\n"
  #     return nil
  #   else
  #     return catalog_items[0]
  #   end
  # end

  def format_catalog_item_status(item, return_color=cyan)
    out = ""
    status_string = item['status'].to_s.upcase
    if status_string == 'IN_CART' || status_string == 'IN CART'
      out << "#{cyan}IN CART#{return_color}"
    elsif status_string == 'ORDERED'
      #out << "#{cyan}#{status_string.upcase}#{return_color}"
      # show the instance/app/execution status instead of the item status ORDERED
      if item['instance']
        out << format_instance_status(item['instance'], return_color)
      elsif item['app']
        out << format_app_status(item['app'], return_color)
      elsif item['execution']
        out << format_job_execution_status(item['execution'], return_color)
      else
        out << "#{cyan}#{status_string.upcase}#{return_color}"
      end
    elsif status_string == 'FAILED'
      out << "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'DELETED'
      out << "#{red}#{status_string.upcase}#{return_color}" # cyan maybe?
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_order_status(cart, return_color=cyan)
    out = ""
    cart_items = cart['items']
    if cart_items.nil? || cart_items.empty?
      out << "#{yellow}EMPTY#{return_color}"
    else
      # status of first item in cart will work i guess...
      item = cart_items.first
      status_string = item['status'].to_s.upcase
      if status_string == "IN_CART"
        # out << "#{cyan}CART (#{cart_items.size()})#{return_color}"
        out << "#{cyan}CART#{return_color}"
      else
        out << format_catalog_item_status(item, return_color)
      end
    end
    out
  end

  def print_order_details(cart, options)
    cart_items = cart['items'] || []
    cart_stats = cart['stats'] || {}
    if cart_items && cart_items.size > 0
      print cyan
      cart_show_columns = {
        #"Order ID" => 'id',
        "Order Name" => 'name',
        "Order Items" => lambda {|it| cart['items'].size },
        "Order Qty" => lambda {|it| cart['items'].sum {|cart_item| cart_item['quantity'] } },
        "Order Status" => lambda {|it| format_order_status(it) },
        #"Order Total" => lambda {|it| format_money(cart_stats['price'], cart_stats['currency']) + " / #{cart_stats['unit']}" },
        #"Items" => lambda {|it| cart['items'].size },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      if options[:details] != true
        cart_show_columns.delete("Order Items")
        cart_show_columns.delete("Order Qty")
        cart_show_columns.delete("Order Status")
      end
      cart_show_columns.delete("Order Name") if cart['name'].to_s.empty?
      # if !cart_show_columns.empty?
      #   print_description_list(cart_show_columns, cart)
      #   print reset, "\n"
      # end

      if options[:details]
        if !cart_show_columns.empty?
          print_description_list(cart_show_columns, cart)
          # print reset, "\n"
        end
        #print_h2 "Cart Items"
        cart_items.each_with_index do |cart_item, index|
          item_config = cart_item['config']
          cart_item_columns = [
            {"ID" => lambda {|it| it['id'] } },
            #{"NAME" => lambda {|it| it['name'] } },
            {"Type" => lambda {|it| it['type']['name'] rescue '' } },
            #{"Qty" => lambda {|it| it['quantity'] } },
            {"Price" => lambda {|it| format_money(it['price'] , it['currency']) } },
            {"Status" => lambda {|it| 
              status_string = format_catalog_item_status(it)
              if it['errorMessage'].to_s != ""
                status_string << " - #{it['errorMessage']}"
              end
              status_string
            } },
            # {"Config" => lambda {|it| format_name_values(it['config']) } },
          ]
          print_h2(index == 0 ? "Item" : "Item #{index+1}", options)
          print as_description_list(cart_item, cart_item_columns, options)
          # print "\n", reset
          if item_config && !item_config.keys.empty?
            print_h2("Configuration", options)
            print as_description_list(item_config, item_config.keys, options)
            print "\n", reset
          end
        end
      else
        if !cart_show_columns.empty?
          print_description_list(cart_show_columns, cart)
          print reset, "\n"
        end
        #print_h2 "Cart Items"
        cart_item_columns = [
          {"ID" => lambda {|it| it['id'] } },
          #{"NAME" => lambda {|it| it['name'] } },
          {"TYPE" => lambda {|it| it['type']['name'] rescue '' } },
          #{"QTY" => lambda {|it| it['quantity'] } },
          {"PRICE" => lambda {|it| format_money(it['price'] , it['currency']) } },
          {"STATUS" => lambda {|it| 
            status_string = format_catalog_item_status(it)
            if it['errorMessage'].to_s != ""
              status_string << " - #{it['errorMessage']}"
            end
            status_string
          } },
          # {"CONFIG" => lambda {|it| 
          #   truncate_string(format_name_values(it['config']), 50)
          # } },
        ]
        print as_pretty_table(cart_items, cart_item_columns)
      end
      print reset,"\n"
      print cyan
      puts "Total: " + format_money(cart_stats['price'], cart_stats['currency']) + " / #{cart_stats['unit']}"
      print reset,"\n"
    else
      print cyan,"Cart is empty","\n",reset
      print reset,"\n"
    end
  end

  def format_job_execution_status(execution, return_color=cyan)
    out = ""
    status_string = execution['status'].to_s.downcase
    if status_string
      if ['complete','success', 'successful', 'ok'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      elsif ['error', 'offline', 'failed', 'failure'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{yellow}#{status_string.upcase}"
      end
    end
    out + return_color
  end

end
