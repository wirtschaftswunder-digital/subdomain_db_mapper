RSpec.describe "staging-demo tenant mapping" do
  let(:environment) { double("environment", test?: false, development?: false, production?: true) }

  before do
    stub_const("Rails", double("Rails", env: environment))
  end

  it "routes staging-demo to its own tenant and rejects unknown subdomains" do
    controller_class = Class.new do
      def self.class_attribute(*); end
      def self.before_action(*); end
      include SubdomainDbMapper::Controller
      attr_accessor :request
    end
    controller = controller_class.new
    allow(controller).to receive(:change_domains)
    allow(SubdomainDbMapper::Database).to receive(:switch)
    controller.request = double(subdomains: ["staging-demo"])
    controller.change_db
    expect(SubdomainDbMapper::Database).to have_received(:switch).with("STAGING-DEMO")

    controller.request = double(subdomains: ["unknown"])
    expect { controller.change_db }.to raise_error(ArgumentError)
  end

  it "rejects a missing database mapping even when this thread has the tenant set" do
    allow(ActiveRecord::Base).to receive(:connection_config).and_return(database: "production")
    allow(SubdomainDbMapper::Database).to receive(:subdomain_db_mappping).with("STAGING-DEMO").and_return("")
    previous_tenant = Thread.current[:subdomain]
    Thread.current[:subdomain] = "STAGING-DEMO"
    expect { SubdomainDbMapper::Database.switch("STAGING-DEMO") }.to raise_error(SubdomainDbMapper::Error)
  ensure
    Thread.current[:subdomain] = previous_tenant
  end

  it "rejects incomplete credentials before connecting" do
    allow(SubdomainDbMapper::Database).to receive(:`).and_return("configured", "configured", "", "configured")
    expect(ActiveRecord::Base).not_to receive(:establish_connection)
    expect { SubdomainDbMapper::Database.send(:change_db, "STAGING-DEMO") }.to raise_error(SubdomainDbMapper::Error)
  end

  it "uses the staging-demo credentials when they are complete" do
    allow(SubdomainDbMapper::Database).to receive(:`).and_return("staging_db", "staging_user", "password", "staging_host")
    expect(ActiveRecord::Base).to receive(:establish_connection).with(hash_including(
      "database" => "staging_db", "username" => "staging_user", "host" => "staging_host"
    ))
    SubdomainDbMapper::Database.send(:change_db, "STAGING-DEMO")
  end
end
