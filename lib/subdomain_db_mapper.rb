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
      unless Rails.env.development? && tenant.blank?
        change_domains
        SubdomainDbMapper::Database.switch(tenant)
      end
    end

    def check_authorization
      logger.debug 'from gem'
      logger.debug session.inspect
      logger.debug cookies.inspect
      id = cookies.encrypted['id']
      if id.blank?
        not_authenticated unless Anbieter.find_by_key(params[:key]).present? #API requests
      else
        @anbieter = User.find(id).anbieter
        if @anbieter.nil?
          redirect_to new_user_path, :notice=>"Sie dürfen auf diese Funktion nicht zugreifen"
        else
          set_cryptkeeper
        end
      end
    end

    private
    def not_authenticated
      redirect_to login_path, alert: "Erst einloggen"
    end

    def set_cryptkeeper
      if request.subdomains.present?
        tenant = request.subdomains(0).first.force_encoding("UTF-8").parameterize.upcase
        ENV['CRYPT_KEEPER_KEY'] = `cat /home/app/webapp/config/env/#{tenant}_CRYPT_KEEPER_KEY`
        ENV['CRYPT_KEEPER_SALT'] = `cat /home/app/webapp/config/env/#{tenant}_CRYPT_KEEPER_SALT`
      end
    end

    def change_domains
      if defined?(Masken) && request.subdomains.present?
        ENV["DOMAIN"] = "#{request.protocol}#{request.domain(2)}"
        ENV["SESSION_DOMAIN"] = "#{request.domain(2)}"
      elsif request.subdomains.present?
        Rails.configuration.x.domain = "#{request.protocol}#{request.domain(2)}"
        ENV["SESSION_DOMAIN"] = "#{request.domain(2)}"
      end
    end
  end

  class Database < ActiveRecord::Base

    def self.switch(tenant)
      tenant = tenant.force_encoding("UTF-8").parameterize.upcase
      JugendreisenBase rescue nil #not initialized by Rails in some apps - like destination, customercenter
      if defined?(JugendreisenBase)
        main_db = JugendreisenBase.connection_config[:database]
      else
        main_db = ActiveRecord::Base.connection_config[:database]
      end
      tenant_connection = main_db.try(:include?, subdomain_db_mappping(tenant))
      tenant_thread = Thread.current[:subdomain] == tenant
      if not (tenant_connection and tenant_thread)
        self.change_db(tenant)
        self.change_db_kc(tenant)
        self.change_db_teamer(tenant)
        self.change_s3(tenant) if defined?(Paperclip)
        self.change_s3_kc(tenant) if defined?(Kundencenter)
        self.change_s3_teamer(tenant)
        Thread.current[:subdomain] = tenant
      end
      logger.debug(Thread.current[:subdomain])
      if defined?(JugendreisenBase)
        logger.debug(JugendreisenBase.connection_config[:database])
      else
        logger.debug(ActiveRecord::Base.connection_config[:database])
      end
    end

    private
    def self.subdomain_db_mappping(tenant)
      if Rails.env.production?
        `cat /home/app/webapp/config/env/#{tenant}_DATABASE`
      else
        "#{tenant.downcase}_development"
      end
    end

    def self.change_db(tenant)
      if Rails.env.development?
        db = YAML::load(ERB.new(File.read(Rails.root.join("config","database.yml"))).result)[tenant.downcase]['development']
      else
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
      if defined?(JugendreisenBase)
        JugendreisenBase.establish_connection(db)
      else
        ActiveRecord::Base.establish_connection(db)
      end
    end

    def self.change_db_kc(tenant)
      KundencenterBase rescue nil #not initialized by Rails in some apps - like destinatiin, customercenter
      if Rails.env.development?
        db = YAML::load(ERB.new(File.read(Rails.root.join("config","database.yml"))).result)["#{tenant.downcase}_db_org"]["development"]
      else
        db = {"adapter"=>"mysql2",
              "encoding"=>"utf8",
              "reconnect"=>false,
              "pool"=>5,
              "timeout"=>5000,
              "port"=>3306,
              "database"=> `cat /home/app/webapp/config/env/#{tenant}_KUNDENCENTER_DATABASE`,
              "username"=> `cat /home/app/webapp/config/env/#{tenant}_KUNDENCENTER_USERNAME`,
              "password"=> `cat /home/app/webapp/config/env/#{tenant}_KUNDENCENTER_PASSWORD`,
              "host"=> `cat /home/app/webapp/config/env/#{tenant}_KUNDENCENTER_HOST`}
      end
      if defined?(Masken)
        MultiTenant::KundencenterBase.establish_connection db
      else
        KundencenterBase.establish_connection db if defined?(KundencenterBase)
      end
    end

    def self.change_db_teamer(tenant)
      TeamerBase rescue nil #not initialized by Rails in some apps
      if defined?(TeamerBase)
        if Rails.env.development?
          db = YAML::load(ERB.new(File.read(Rails.root.join("config","database.yml"))).result)["#{tenant.downcase}_db_teamer"]['development']
        else
          db = {"adapter"=>"mysql2",
                "encoding"=>"utf8",
                "reconnect"=>false,
                "pool"=>5,
                "timeout"=>5000,
                "port"=>3306,
                "database"=> `cat /home/app/webapp/config/env/#{tenant}_TEAMER_DATABASE`,
                "username"=> `cat /home/app/webapp/config/env/#{tenant}_TEAMER_USERNAME`,
                "password"=> `cat /home/app/webapp/config/env/#{tenant}_TEAMER_PASSWORD`,
                "host"=> `cat /home/app/webapp/config/env/#{tenant}_TEAMER_HOST`}
        end
        if defined?(TeamerApp) or defined?(TeamManagerApp)
          ApplicationRecord.establish_connection(db)
        else
         TeamerBase.establish_connection(db)
        end
      end
    end

    def self.change_s3(tenant)
      Paperclip::Attachment.default_options.update({
        storage: :s3,
        s3_protocol: :https,
        preserve_files: true,
        s3_credentials: {
            bucket: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_BUCKET`,
            access_key_id: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_ACCESS_KEY_ID`,
            secret_access_key: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_SECRET_ACCESS_KEY`,
            region: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_REGION`,
            s3_host_name: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_HOST`
        },
        s3_options: {
            force_path_style: true
        },
        s3_region: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_REGION`,
        s3_headers: {
          'Cache-Control' => 'max-age=3153600',
          'Expires' => 2.years.from_now.httpdate
        }
      })
      if defined?(Aws)
        Aws.config.update({
          force_path_style: true,
          credentials: Aws::Credentials.new(`cat /home/app/webapp/config/env/#{tenant}_IMAGES_ACCESS_KEY_ID`, `cat /home/app/webapp/config/env/#{tenant}_IMAGES_SECRET_ACCESS_KEY`),
          region: `cat /home/app/webapp/config/env/#{tenant}_IMAGES_REGION`
        })
        ENV['IMAGES_BUCKET'] = `cat /home/app/webapp/config/env/#{tenant}_IMAGES_BUCKET`
      end
    end

    def self.change_s3_kc(tenant)
      CarrierWave.configure do |config|
        config.aws_bucket = `cat /home/app/webapp/config/env/#{tenant}_KC_BUCKET`
        config.aws_acl = 'private'
        config.aws_credentials = {
          access_key_id:     `cat /home/app/webapp/config/env/#{tenant}_KC_ACCESS_KEY_ID`,
          secret_access_key: `cat /home/app/webapp/config/env/#{tenant}_KC_SECRET_ACCESS_KEY`,
          region:            `cat /home/app/webapp/config/env/#{tenant}_KC_REGION`,
          stub_responses:    Rails.env.test? # Optional, avoid hitting S3 actual during tests
        }
        config.storage = :aws
      end
    end

    def self.change_s3_teamer(tenant)
      if Rails.env.production?
        if defined?(TeamerApp) or defined?(TeamManagerApp)
          #Aws.config.update({
          #  credentials: Aws::Credentials.new(`cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_ACCESS_KEY_ID`, `cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_SECRET_ACCESS_KEY`)
          #})
          ActiveStorage::Blob.service.client.client.config.credentials.instance_variable_set(:@access_key_id, `cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_ACCESS_KEY_ID`)
          ActiveStorage::Blob.service.bucket.client.config.access_key_id = `cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_ACCESS_KEY_ID`
          ActiveStorage::Blob.service.client.client.config.credentials.instance_variable_set(:@secret_access_key, `cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_SECRET_ACCESS_KEY`)
          ActiveStorage::Blob.service.bucket.client.config.secret_access_key = `cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_SECRET_ACCESS_KEY`
          ActiveStorage::Blob.service.bucket.instance_variable_set(:@name, `cat /home/app/webapp/config/env/#{tenant}_TEAMER_S3_BUCKET`)
        end
      end
    end
  end

end
