require "subdomain_db_mapper/version"
require "active_record"
#todo: put Controller and Database in files
#require "subdomain_db_mapper/controller"
module SubdomainDbMapper
  class Error < StandardError; end

  module Controller
    extend ActiveSupport::Concern

    included do
      # anything you would want to do in every controller, for example: add a class attribute
      class_attribute :class_attribute_available_on_every_controller, instance_writer: false
    end

    def self.included(klass)
      klass.before_action :change_db
      klass.before_action :check_authorization
    end

    def change_db
      tenant = request.subdomains(0).first
      SubdomainDbMapper::Database.switch(tenant) unless Rails.env.development? && tenant.blank?
    end

    # To be used as before_action.
    # Will trigger check_authorization and DB change
    def check_authorization
      id = session[:id] || cookies.encrypted['id']
      if id.blank?
        redirect_to login_path, alert: "Erst einloggen"
      else
        @anbieter = User.find(id).anbieter
        if @anbieter.nil?
          redirect_to new_user_path, :notice=>"Sie dürfen auf diese Funktion nicht zugreifen"
        else
          Rails.configuration.x.domain = "#{request.protocol}#{request.domain(2)}"
          session[:id] = id.to_s # for missing session id
          session[:user_id] = id.to_s # for sorcery login
        end
      end
    end
  end

  class Database < ActiveRecord::Base

    def self.switch(tenant)
      tenant = tenant.parameterize.upcase
      tenant_connection = ActiveRecord::Base.connection_config[:database].try(:include?, subdomain_db_mappping(tenant))
      tenant_thread = Thread.current[:subdomain] == tenant
      env = Rails.env.production? ? "production" : "development"
      if not (tenant_connection and tenant_thread)
        self.change_db(tenant, env)
        self.change_s3(tenant) if defined?(Paperclip)
        Thread.current[:subdomain] = tenant
      end
      logger.debug(Thread.current[:subdomain])
      logger.debug(ActiveRecord::Base.connection_config[:database])
    end

    private
    def self.subdomain_db_mappping(tenant)
      if Rails.env.production?
        `cat /home/app/webapp/config/env/#{tenant}_DATABASE`
      else
        "#{tenant.downcase}_development"
      end
    end

    def self.change_db(tenant, env)
      if env == 'development'
        db = YAML::load(ERB.new(File.read(Rails.root.join("config","database.yml"))).result)[tenant.downcase][env]
      else
        Rails.application.config.session_store :cookie_store, domain: ENV["SESSION_DOMAIN"], key: ENV["SESSION_KEY"], tld_length: 2, secure: true
        Rails.application.config.secret_key_base = `cat /home/app/webapp/config/env/#{tenant}_KEY_BASE`
        db = {"adapter"=>"mysql2",
              "encoding"=>"utf8",
              "reconnect"=>false,
              "pool"=>5,
              "timeout"=>5000,
              "port"=>3306,
              "database"=> `cat /home/app/webapp/config/env/#{tenant}_DATABASE`,
              "username"=> `cat /home/app/webapp/config/env/#{tenant}_USERNAME`,
              "password"=> `cat /home/app/webapp/config/env/#{tenant}_PASSWORD`,
              "host"=> `cat /home/app/webapp/config/env/#{tenant}_HOST`}
      end
      ActiveRecord::Base.establish_connection(db)# rescue nil
    end

    def self.change_s3(tenant)
      Paperclip::Attachment.default_options.update({
        storage: :s3,
        s3_protocol: :https,
        preserve_files: true,
        s3_credentials: {
            bucket: `cat /home/app/webapp/config/env/#{tenant}_FILES_BUCKET`,
            access_key_id: `cat /home/app/webapp/config/env/#{tenant}_FILES_ACCESS_KEY_ID`,
            secret_access_key: `cat /home/app/webapp/config/env/#{tenant}_FILES_SECRET_ACCESS_KEY`,
            region: `cat /home/app/webapp/config/env/#{tenant}_FILES_REGION`,
            s3_host_name: `cat /home/app/webapp/config/env/#{tenant}_FILES_HOST`
        },
        s3_options: {
            force_path_style: true
        },
        s3_region: `cat /home/app/webapp/config/env/#{tenant}_FILES_REGION`,
        s3_headers: {
          'Cache-Control' => 'max-age=3153600',
          'Expires' => 2.years.from_now.httpdate
        }
      })
    end
  end

end
