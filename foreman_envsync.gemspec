# frozen_string_literal: true

require_relative "lib/foreman_envsync/version"

Gem::Specification.new do |spec|
  spec.name          = "foreman_envsync"
  spec.version       = ForemanEnvsync::VERSION
  spec.authors       = ["Joshua Hoblitt"]
  spec.email         = ["josh@hoblitt.com"]

  spec.summary       = "Sync pupperserver envs with foreman"
  spec.homepage      = "https://github.com/lsst-it/foreman_envsync"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lsst-it/foreman_envsync"
  spec.metadata["changelog_uri"] = "https://github.com/lsst-it/foreman_envsync/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "hammer_cli"
  spec.add_runtime_dependency "hammer_cli_foreman"
  spec.add_runtime_dependency "hammer_cli_foreman_puppet"
  spec.add_runtime_dependency "rest-client", "~> 2.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "false"
end
