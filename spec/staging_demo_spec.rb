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
end
