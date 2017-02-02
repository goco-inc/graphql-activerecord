# Changelog

# 0.10.0
There are a few breaking changes:
- Added automatic nullability checking for attributes. It’s enabled by default; see the README for more info.
- The gem now assumes that the object types for your models are called "ModelNameType" instead of "ModelNameGraph",
  to bring it more in line with common practice. You can get the old behavior by adding this to an initializer:
  
```ruby
  GraphQL::Models.model_to_graphql_type -> (model_class) { "#{model_class.name}Graph".safe_constantize }
```

## 0.9.0
- Support for graphql version 1.2.1 and higher, but it no longer works with 0.x versions

## 0.8.0
- Updated runtime dependency requirements

## 0.7.2

### Breaking Changes
- Changed models are no longer reloaded when you call `save!` on a mutator
