$LOAD_PATH.push File.expand_path('../lib', __FILE__)

require 'graphql/models/version'

Gem::Specification.new do |s|
  s.name = 'graphql-activerecord'
  s.version = GraphQL::Models::VERSION
  s.date = Date.today.to_s
  s.summary = "ActiveRecord helpers for GraphQL + Relay"
  s.description = "Build Relay-compatible GraphQL schemas based on ActiveRecord models"
  s.homepage = "http://github.com/goco-inc/graphql-activerecord"
  s.authors = ["Ryan Foster"]
  s.email = ["theorygeek@gmail.com"]
  s.license = "MIT"
  s.required_ruby_version = '>= 2.1.0'

  s.files = Dir["{lib}/**/*", "MIT_LICENSE", "readme.md"]
  s.test_files = Dir["spec/**/*"]

  s.add_runtime_dependency "graphql", "~> 0.11.0"
  s.add_runtime_dependency "graphql-relay", "~> 0.7.1"
end
