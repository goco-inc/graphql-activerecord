# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'graphql/models/version'

Gem::Specification.new do |spec|
  spec.name          = "graphql-activerecord"
  spec.version       = GraphQL::Models::VERSION
  spec.authors       = ["Ryan Foster"]
  spec.email         = ["theorygeek@gmail.com"]

  spec.summary = "ActiveRecord helpers for GraphQL + Relay"
  spec.description = "Build Relay-compatible GraphQL schemas based on ActiveRecord models"
  spec.homepage =  "http://github.com/goco-inc/graphql-activerecord"
  spec.license = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "activesupport", "~> 4.2"
  spec.add_runtime_dependency "activerecord", "~> 4.2"
  spec.add_runtime_dependency "graphql", "~> 0.13.0"
  spec.add_runtime_dependency "graphql-batch", "~> 0.2.1"
  spec.add_runtime_dependency 'graphql-relay', '~> 0.9.5'

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
