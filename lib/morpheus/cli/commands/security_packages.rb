require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityPackagesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :'security-packages'
  set_command_description "View and manage security packages."
  register_subcommands :list, :get, :add, :update, :remove

  # RestCommand settings
  register_interfaces :security_packages, :security_package_types
  set_rest_has_type true
  # set_rest_type :security_package_types

  protected

  def build_list_options(opts, options, params)
    opts.on('-l', '--label LABEL', String, "Filter by label (keyword).") do |val|
      params['label'] = val
    end
    # build_standard_list_options(opts, options)
    super
  end

  def security_package_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Labels" => lambda {|it| format_list(it['labels'], '', 3) rescue '' },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Description" => 'description',
    }
  end

  def security_package_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Labels" => lambda {|it| format_list(it['labels'], '', 3) rescue '' },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      # "Source" => 'sourceType',
      "URL" => 'url',
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_security_package_option_types()
    [
      {'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Security Package Type', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        api_client.security_package_types.list({max:10000})['securityPackageTypes'].collect { |it| {"name" => it["name"], "value" => it["code"]} }
      }, 'required' => true, 'defaultValue' => 'SCAP Package'},      
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'shorthand' => '-l', 'fieldName' => 'labels', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'noPrompt' => true, 'processValue' => lambda {|val| val.is_a?(Array) ? val : (val.nil? ? nil : val.to_s.split(",")) }},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
      # {'code' => 'securityPackage.sourceType', 'fieldName' => 'sourceType', 'fieldLabel' => 'Source', 'type' => 'select', 'selectOptions' => [{'name'=>'url','value'=>'url'}], 'defaultValue' => 'url', 'required' => true},
      # {'code' => 'securityPackage.sourceType', 'fieldContext' => 'file', 'fieldName' => 'sourceType', 'fieldLabel' => 'Source', 'type' => 'hidden', 'defaultValue' => 'url', 'required' => true},
      {'fieldName' => 'url', 'fieldLabel' => 'URL', 'type' => 'text', 'required' => true, 'description' => "URL to download the security package zip file from"},
      # {'fieldName' => 'file', 'fieldLabel' => 'File Content', 'type' => 'file-content', 'required' => true},
    ]
  end

  def add_security_package_advanced_option_types()
    []
  end

  def update_security_package_option_types()
    option_types = add_security_package_option_types.collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
    option_types.reject! {|it| it['fieldName'] == 'type' }
    option_types
  end

  def update_security_package_advanced_option_types()
    add_security_package_advanced_option_types().collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
  end

end
