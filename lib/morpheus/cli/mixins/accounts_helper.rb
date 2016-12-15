require 'table_print'
require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes 
# Provides common methods for fetching and printing accounts, roles, and users.
# The including class must establish @accounts_interface, @roles_interface, @users_interface
module Morpheus::Cli::AccountsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def find_account_by_id(id)
    raise "#{self.class} has not defined @accounts_interface" if @accounts_interface.nil?
    begin
      json_response = @accounts_interface.get(id.to_i)
      return json_response['account']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Account not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_account_by_name(name)
    raise "#{self.class} has not defined @accounts_interface" if @accounts_interface.nil?
    accounts = @accounts_interface.list({name: name.to_s})['accounts']
    if accounts.empty?
      print_red_alert "Account not found by name #{name}"
      return nil
    elsif accounts.size > 1
      print_red_alert "#{accounts.size} accounts found by name #{name}"
      print_accounts_table(accounts, {color: red})
      print_red_alert "Try using -A ID instead"
      print reset,"\n"
      return nil
    else
      return accounts[0]
    end
  end

  def find_account_from_options(options)
    account = nil
    if options[:account_name]
      account = find_account_by_name(options[:account_name])
      exit 1 if account.nil?
    elsif options[:account_id]
      account = find_account_by_id(options[:account_id])
      exit 1 if account.nil?
    else
      account = nil # use current account
    end
    return account
  end

  def find_role_by_id(account_id, id)
    raise "#{self.class} has not defined @roles_interface" if @roles_interface.nil?
    begin
      json_response = @roles_interface.get(account_id, id.to_i)
      return json_response['role']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Role not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_role_by_name(account_id, name)
    raise "#{self.class} has not defined @roles_interface" if @roles_interface.nil?
    roles = @roles_interface.list(account_id, {authority: name.to_s})['roles']
    if roles.empty?
      print_red_alert "Role not found by name #{name}"
      return nil
    elsif roles.size > 1
      print_red_alert "#{roles.size} roles by name #{name}"
      print_roles_table(roles, {color: red})
      print reset,"\n\n"
      return nil
    else
      return roles[0]
    end
  end

  alias_method :find_role_by_authority, :find_role_by_name

  def find_user_by_id(account_id, id)
    raise "#{self.class} has not defined @users_interface" if @users_interface.nil?
    begin
      json_response = @users_interface.get(account_id, id.to_i)
      return json_response['user']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "User not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_by_username(account_id, username)
    raise "#{self.class} has not defined @users_interface" if @users_interface.nil?
    users = @users_interface.list(account_id, {username: username.to_s})['users']
    if users.empty?
      print_red_alert "User not found by username #{username}"
      return nil
    elsif users.size > 1
      print_red_alert "#{users.size} users by username #{username}"
      print_users_table(users, {color: red})
      print reset,"\n\n"
      return nil
    else
      return users[0]
    end
  end

  def print_accounts_table(accounts, opts={})
    table_color = opts[:color] || cyan
    rows = accounts.collect do |account|
      status_state = nil
      if account['active']
        status_state = "#{green}ACTIVE#{table_color}"
      else
        status_state = "#{red}INACTIVE#{table_color}"
      end
      {
        id: account['id'], 
        name: account['name'], 
        description: account['description'], 
        role: account['role'] ? account['role']['authority'] : nil, 
        status: status_state,
        dateCreated: format_local_dt(account['dateCreated']) 
      }
    end
    
    print table_color
    tp rows, [
      :id, 
      :name, 
      :description, 
      :role, 
      {:dateCreated => {:display_name => "Date Created"} },
      :status
    ]
    print reset
  end

  def format_role_type(role)
    str = ""
    if role['roleType'] == "account"
      str = "Account"
    elsif role['roleType'] == "user"
      str = "User"
    else
      if role['scope'] == 'Account'
        str = "Legacy"
      else
        str = "Admin" # System Admin
      end
    end
    # if role['scope'] && role['filterType'] != 'Account'
    #   str = "(System) #{str}"
    # end
    return str
  end

  def print_roles_table(roles, opts={})
    table_color = opts[:color] || cyan
    # tp roles, [
    #   'id',
    #   'name',
    #   'description',
    #   'scope',
    #   {'dateCreated' => {:display_name => "Date Created", :display_method => lambda{|it| format_local_dt(it['dateCreated']) } } }
    # ]
    rows = roles.collect do |role|
      {
        id: role['id'], 
        name: role['authority'], 
        description: role['description'], 
        scope: role['scope'],
        multitenant: role['multitenant'] ? 'Yes' : 'No',
        type: format_role_type(role),
        owner: role['owner'] ? role['owner']['name'] : "System",
        dateCreated: format_local_dt(role['dateCreated']) 
      }
    end
    print table_color
    tp rows, [
      :id, 
      :name, 
      :description, 
      # opts[:is_master_account] ? :scope : nil,
      opts[:is_master_account] ? :type : nil,
      opts[:is_master_account] ? :multitenant : nil,
      opts[:is_master_account] ? :owner : nil,
      {:dateCreated => {:display_name => "Date Created"} }
    ].compact
    print reset
  end

  def print_users_table(users, opts={})
    table_color = opts[:color] || cyan
    rows = users.collect do |user|
      {id: user['id'], username: user['username'], first: user['firstName'], last: user['lastName'], email: user['email'], role: format_user_role_names(user), account: user['account'] ? user['account']['name'] : nil}
    end
    print table_color
    tp rows, :id, :account, :first, :last, :username, :email, :role
    print reset
  end

  def format_user_role_names(user)
    role_names = ""
    if user && user['roles']
      roles = user['roles']
      roles = roles.sort {|a,b| a['authority'].to_s.downcase <=> b['authority'].to_s.downcase }
      role_names = roles.collect {|r| r['authority'] }.join(', ')
    end
    role_names
  end

  def get_access_string(val)
    val ||= 'none'
    if val == 'none'
      "#{white}#{val.to_s.capitalize}#{cyan}"
    else
      "#{green}#{val.to_s.capitalize}#{cyan}"
    end
  end

end
