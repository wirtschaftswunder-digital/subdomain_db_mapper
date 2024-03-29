require_relative 'lib/subdomain_db_mapper/version'

Gem::Specification.new do |spec|
  spec.name          = "subdomain_db_mapper"
  spec.version       = SubdomainDbMapper::VERSION
  spec.authors       = ["marcelbelledin@o2online.de"]
  spec.email         = ["marcelbelledin@o2online.de"]

  spec.summary       = %q{ add subdomain DB mapping functionality}
  #spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = "http://www.wirtschaftswunder.digital"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = 'http://git.webprojektfabrik.de'

  spec.metadata["homepage_uri"] = spec.homepage
  #spec.metadata["source_code_uri"] = 'http://git.webprojektfabrik.de'
  #spec.metadata["changelog_uri"] = 'http://git.webprojektfabrik.de'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
