
module SubdomainDbMapper
    class Railtie < Rails::Railtie
      initializer "subdomain_db_mapper.action_controller" do
      ActiveSupport.on_load(:action_controller) do
        puts "Extending #{self} with SubdomainDbMapper::Controller"
        # ActionController::Base gets a method that allows controllers to include the new behavior
        include SubdomainDbMapper::Controller # ActiveSupport::Concern
      end
    end
  end