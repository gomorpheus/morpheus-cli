# Mixin for Morpheus::Cli command classes 
# Provides common methods for fetching and printing accounts, roles, and users.
# The including class must establish @accounts_interface, @roles_interface, @users_interface
module Morpheus::Cli::AccountsHelper

  def find_account_by_id(id)
    raise "#{self.class} has not defined @accounts_interface" if @accounts_interface.nil?
    account = @accounts_interface.get(id)['account']
    if account.nil?
      print_red_alert "Account not found by id #{id}"
      return nil
    else
      return account
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
      print reset,"\n\n"
      return nil
    else
      return accounts[0]
    end
  end

  def find_role_by_id(account_id, id)
    raise "#{self.class} has not defined @roles_interface" if @roles_interface.nil?
    role = @roles_interface.get(account_id, id)['role']
    if role.nil?
      print_red_alert "Role not found by id #{id}"
      return nil
    else
      return role
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
    user = @users_interface.get(account_id, id)['user']
    if user.nil?
      print_red_alert "User not found by id #{id}"
      return nil
    else
      return user
    end
  end

  def find_user_by_username(account_id, username)
    raise "#{self.class} has not defined @users_interface" if @users_interface.nil?
    users = @users_interface.list(account_id, {username: username.to_s})['users']
    if users.empty?
      print_red_alert "User not found by username #{username}\n\n"
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
        owner: role['owner'] ? role['owner']['name'] : nil, 
        dateCreated: format_local_dt(role['dateCreated']) 
      }
    end
    print table_color
    tp rows, [
      :id, 
      :name, 
      :description, 
      :scope, 
      :owner, 
      {:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end

  def print_users_table(users, opts={})
    table_color = opts[:color] || cyan
    rows = users.collect do |user|
      {id: user['id'], username: user['username'], first: user['firstName'], last: user['lastName'], email: user['email'], role: user['role'] ? user['role']['authority'] : nil, account: user['account'] ? user['account']['name'] : nil}
    end
    print table_color
    tp rows, :id, :account, :first, :last, :username, :email, :role
    print reset
  end

  def print_red_alert(msg)
    print red, bold, "\n#{msg}\n\n", reset
  end

end
