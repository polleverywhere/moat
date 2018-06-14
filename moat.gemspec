require File.expand_path("lib/moat/version", __dir__)

Gem::Specification.new do |gem|
  gem.name               = "moat"
  gem.version            = Moat::VERSION
  gem.license            = "MIT"
  gem.authors            = ["Poll Everywhere"]
  gem.email              = ["geeks@polleverywhere.com"]
  gem.homepage           = "https://github.com/polleverywhere/moat"
  gem.summary            = "A small authorization library"
  gem.description        = "Moat is an small authorization library built for Ruby (primarily Rails) web applications"
  gem.files              = `git ls-files`.split("\n")
  gem.test_files         = `git ls-files -- spec/*`.split("\n")
  gem.require_paths      = ["lib"]
  gem.extra_rdoc_files   = ["README.md"]
  gem.rdoc_options       = ["--main", "README.md"]

  gem.add_development_dependency("rspec", "~> 3.5")
  gem.add_development_dependency("rubocop", "~> 0.57.2")
end
