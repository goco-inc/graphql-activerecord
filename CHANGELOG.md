# Changelog

# 0.10.0
There are a few breaking changes:
- Added automatic nullability checking for attributes. It’s enabled by default; see the README for more info.
- The gem now assumes that the object types for your models are called "ModelNameType" instead of "ModelNameGraph",
  to bring it more in line with common practice. You can get the old behavior by adding this to an initializer:
  
```ruby
  GraphQL::Models.model_to_graphql_type -> (model_class) { "#{model_class.name}Graph".safe_constantize }
```

- Fixed a bug with the `has_many_connection` helper, which deserves some explanation. This helper constructs a
  connection field that returns an ActiveRecord relation. There isn't an easy way to inject functionality into the resolvers
  that are used by connections (to my knowledge) - eg, by using middleware - so this helper had some GoCo-specific code
  baked into it, which probably caused odd errors about an undefined constant `GraphSupport` whenever it was used. I can’t
  quite remove that functionality yet, but I did take it one step closer by having the code first check to see if the constant
  was defined, and bypass it if it’s not.

## 0.9.0
- Support for graphql version 1.2.1 and higher, but it no longer works with 0.x versions

## 0.8.0
- Updated runtime dependency requirements

## 0.7.2

### Breaking Changes
- Changed models are no longer reloaded when you call `save!` on a mutator
