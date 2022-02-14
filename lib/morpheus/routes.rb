# Routes is a module to provide a way to look up routes in the Morpheus UI.
# Examples:
#   Routes.lookup("users") == "/admin/users"
#   Routes.lookup("instances") == "/provisioning/instances"
#
#   puts "All routes", Morpheus::Routes.routes
#
module Morpheus::Routes

  # A static site map for the Morpheus UI.
  # todo: move to YAML or load from api
  SITE_MAP = {
    operations: {
      dashboard: {},
      reports: {},
      analytics: {},
      guidance: {},
      wiki: {},
      costing: {
        budgets: {},
        invoices: {},
        usage: {},
      },
      approvals: {},
      activity: {},
      alarms: {},
    },
    provisioning: {
      instances: {},
      apps: {},
      catalog: {},
      jobs: {},
      executions: {},
      code: {
        respositories: {},
        deployments: {},
        # integrations: {}, # Integrations
      },
    },
    library: {
      automation: [
        "#!tasks",
        "#!workflows",
        "#!thresholds",
        "#!power-schedules",
        "#!execute-schedules",
      ],
      blueprints: [
        "#instance-types",
        "#!instance-type-layouts",
        "#!container-types",
        "#!app-templates", # App Blueprints (blueprints)
        "#!catalog-items",
        "#!compute-type-layouts", # Cluster Layouts
      ],
      :'virtual-images' => {},
      options: [
        "#!option-type-lists", # Option Lists
      ],
      templates: [
        "#!specs",
        "#!files",
        "#!scripts",
        "#!security-specs",
      ],
      services: {}, # Integrations

    },
    infrastructure: {
      groups: {},
      clouds: {},
      clusters: {},
      servers: {}, # Hosts (still used for loading by id)
      inventory: [ # Compute
        "#!hosts",
        "#!virtual-machines",
        "#!containers",
        "#!resources",
        "#!bare-metal",
      ],
      networks: {},
      :'load-balancers' => {},
      storage: {
        buckets: {},  
        shares: {},  # File Shares
        volumes: {},  
        :'data-stores' => {}, # ugh, should be datastores
        servers: {}, # Storage Servers
      },
      trust: [
        "#!credentials",
        "#!certificates",
        "#!keypairs",
        "#!services",
      ],
      boot: [
        "#!mappings",
        "#!boot-menus",
        "#!answerfiles",
        "#!boot-images",
        "#!macs",
      ],
    },
    backups: {

    },
    monitoring: {
      status: {},
      logs: {},
      apps: {},
      checks: {},
      groups: {},
      incidents: {},
      contacts: {},
      :'alert-rules' => {}, 
    },
    tools: {
      cypher: {},
      archives: {
        buckets: {},
      },
      :'image-builder' => {},
      :vdi => {}
    },
    admin: {
      accounts: {}, # Tenants
      :'service-plans' => [
        "#prices",
        "#pricesets"
      ],
      roles: {},
      users: {},
      :'user-groups' => {},
      integrations: {},
      policies: {},
      health: ["logs"],
      settings: {},
    },
    :'user-settings' => {}, # User Settings (Profile)
  } unless defined?(SITE_MAP)

  # A list of routes generated from the site map and cached
  @@routes = nil
  
  # @return an array of well known Morpheus UI routes.
  def self.routes
    if !@@routes
      @@routes = build_routes(SITE_MAP)
    end
    return @@routes
  end

  # lookup a route in the morpheus UI
  # @param path [String] The input to lookup a route for eg. "dashboard"
  # @return full path like "/operations/dashboard"
  def self.lookup(input)
    path = input.to_s
    if path.start_with?("/")
      # absolute path is being looked up
      return path
    else
      # todo: make this smarter, regex, case insensitive, etc
      # find the one with smallest match index

      # map well known aliases
      case(path.underscore.singularize)
      when "server","host","vm","virtual-machine"
        # actually should be "/infrastructure/inventory" unless id is passed, show route uses /servers though
        path = "/infrastructure/servers"
      when "compute"
        path = "/infrastructure/inventory"
      when "tenant"
        path = "/admin/accounts"
      end
      # dasherize path and attempt to match the plural first
      plural_path = path.pluralize
      paths = [path.dasherize]
      if plural_path != path
        paths.unshift(plural_path.dasherize)
      end

      best_route = nil
      best_index = nil
      best_prefix_words = nil
      paths.each do |p|
        if best_route.nil?
          self.routes.each do |it|
            match_index = it.index(p)
            if match_index
              prefix_route = match_index == 0 ? "" : it[0..(match_index-1)]
              prefix_words = prefix_route.split("/")
              #if best_index.nil? || match_index < best_index
              if best_prefix_words.nil? || prefix_words.size < best_prefix_words.size
                best_route = it
                best_index = match_index
                best_prefix_words = prefix_words
              end
            end
          end
        end
      end
      if best_route
        return best_route
      else
        # no match found
        return nil
      end
    end
    
  end

  protected 

  # build_routes constructs an array of routes (paths) 
  # This traversing the route map recursively and appends paths to output
  # @params route_map [Hash] map of routes
  # @params context [String] the current content
  # @params output [Array] the list of route paths being constructed for return
  # @return array like ["/operations", "/operations/dashboard", "/admin", "/etc"]
  def self.build_routes(route_map, context="", output = nil)
    if output.nil?
      output = []
    end
    route_map.each do |k,v|
      leaf_path = "#{context}/#{k}"
      output << leaf_path
      if v.is_a?(Hash)
        build_routes(v, leaf_path, output)
      elsif v.is_a?(Array)
        v.each do |obj|
          if obj.is_a?(Hash)
            build_routes(obj, leaf_path, output)
          elsif obj.is_a?(Symbol) || obj.is_a?(String)
            # route leaf type not handled
            output << "#{leaf_path}/#{obj}"
          else
            # route leaf type not handled
          end
        end
      else
        # route leaf type not handled
      end
    end
    return output
  end

  
end
