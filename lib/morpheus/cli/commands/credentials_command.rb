require 'morpheus/cli/cli_command'

class Morpheus::Cli::CredentialsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :'credentials'
  set_command_description "View and manage credentials."
  register_subcommands :list, :get, :add, :update, :remove

  # RestCommand settings
  register_interfaces :credentials, :credential_types
  set_rest_has_type true
  # set_rest_type :credential_types

  protected

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(credential_column_definitions(options, record), record, options)
      print reset,"\n"
    end
  end

  def credential_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
    }
  end

  def credential_column_definitions(options, credential)
    columns = [
      {"ID" => 'id' },
      {"Name" => 'name' },
      {"Description" => 'description' },
      {"Type" => lambda {|it| it['type'] ? it['type']['name'] : '' } },
      {"Enabled" => lambda {|it| format_boolean(it['enabled']) } },
      {"Created" => lambda {|it| format_local_dt(it['dateCreated']) } },
      {"Updated" => lambda {|it| format_local_dt(it['lastUpdated']) } }
    ]
    type_code = credential['type']['code']
    if type_code == "access-key-secret"
      columns += [
        {"Access Key" => lambda {|it| it['accessKey'] } },
        {"Secret Key" => lambda {|it| it['secretKey'] } },
      ]
    elsif type_code == "client-id-secret"
      columns += [
        {"Client ID" => lambda {|it| it['clientId'] } },
        {"Client Secret" => lambda {|it| it['clientSecret'] } },
      ]
    elsif type_code == "email-private-key"
      columns += [
        {"Email" => lambda {|it| it['email'] } },
        {"Private Key" => lambda {|it| it['authKey'] ? it['authKey']['name'] : '' } },
      ]
    elsif type_code == "tenant-username-keypair"
      columns += [
        {"Tenant" => lambda {|it| it['tenant'] } },
        {"Username" => lambda {|it| it['username'] } },
        {"Private Key" => lambda {|it| it['authKey'] ? it['authKey']['name'] : '' } },
      ]
    elsif type_code == "username-api-key"
      columns += [
        {"Username" => lambda {|it| it['username'] } },
        {"API Key" => lambda {|it| it['apiKey'] } },
      ]
    elsif type_code == "username-key"
      columns += [
        {"Username" => lambda {|it| it['username'] } },
        {"Private Key" => lambda {|it| it['authKey'] ? it['authKey']['name'] : '' } },
      ]
    elsif type_code == "username-password"
      columns += [
        {"Username" => lambda {|it| it['username'] } },
        {"Password" => lambda {|it| it['password'] } },
      ]
    elsif type_code == "username-password-key"
      columns += [
        {"Username" => lambda {|it| it['username'] } },
        {"Password" => lambda {|it| it['password'] } },
        {"Private Key" => lambda {|it| it['authKey'] ? it['authKey']['name'] : '' } },
      ]
    end
    columns += [
      {"Created" => lambda {|it| format_local_dt(it['dateCreated']) } },
      {"Updated" => lambda {|it| format_local_dt(it['lastUpdated']) } },
    ]
    return columns
  end

  def add_credential_option_types()
    [
      {'fieldName' => 'integration.id', 'fieldLabel' => 'Credential Store', 'type' => 'select', 'optionSource' => 'credentialIntegrations'},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
#      {'fieldName' => 'type', 'fieldLabel' => 'Credential Type', 'type' => 'select', 'optionSource' => 'credentialTypes', 'required' => true},
    ]
  end

  def add_credential_advanced_option_types()
    []
  end

  def update_credential_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox'},
    ]
  end

  def update_credential_advanced_option_types()
    add_credential_advanced_option_types()
  end

end
