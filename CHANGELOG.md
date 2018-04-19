# Changelog

# 0.13.0
Changed the way that null values are handled inside of mutators. Take a look at [(#49)](https://github.com/goco-inc/graphql-activerecord/pull/49)
for details. If you need to get back to the old behavior (ie, `unsetFields`), you can either:
- Add the `legacy_nulls: true` option when defining your mutator, or
- Set `GraphQL::Models.legacy_nulls = true` in an initializer

# 0.12.6
- Fixed a bug when you used a `nested` mutator, and provided a symbol for the `:name` kwarg
- Fixed a bug where the `context` parameter was not being passed to `MutationHelpers::match_inputs_to_models`

# 0.12.5
Fixed a bug where `titleize` is sometimes called on symbols.

# 0.12.4
Added the `GraphQL::Models.unknown_scalar` option (#45)

# 0.12.3
- If possible, try to get the description for a field from the column's comment in the database. (#40)
- Automatically generated union types (for polymorphic associations) used `demodulize` on the class name. If your model is `Name::Spaced`, this fixes a bug where it generates an invalid name. (#42)

# 0.12.2
In mutators, the gem now supports updating nested models, where the `find_by` option specifies an ID field. This works similarly
to input fields that accept ID values: it expects a global ID value to be provided, and uses your configured `model_from_id` proc
to get the model's database ID.

# 0.12.1
Updates the gemspec to support Rails 5

# 0.12.0
This version is focussed on compatibility with the GraphQL 1.5.10. Changes are relatively minor, and mostly are in response to the udpated way that connections are handled in the graphql gem now.

Breaking Changes:
The middleware that the gem uses for preloading associations has been replaced with instrumentation. So instead of this:
```ruby
Schema.define do
  # other stuff
  middleware GraphQL::Models::Middleware.new
end
```
You should do this:
```ruby
Schema.define do
  # other stuff
  instrument :field, GraphQL::Models::Instrumentation.new
end
```
If you were using the `skip_nil_models` option to force your field resolvers to be invoked even when the model ends up not existing, it is available on instrumentation.

# 0.11.0
Breaking Bug Fix: Turns out that 0.10.0 was _supposed_ to introduce (non)nullability on attributes, but it didn’t quite work. That’s
fixed in 0.11.0 (and, I _really_ need to write some tests for this gem).

# 0.10.0
There are a few breaking changes:
- Added automatic nullability checking for attributes. It’s enabled by default; see the README for more info.
- The gem now assumes that the object types for your models are called "ModelNameType" instead of "ModelNameGraph",
  to bring it more in line with common practice. You can get the old behavior by adding this to an initializer:

```ruby
  GraphQL::Models.model_to_graphql_type = -> (model_class) { "#{model_class.name}Graph".safe_constantize }
```

- Fixed a bug with the `has_many_connection` helper, which deserves some explanation. This helper constructs a
  connection field that returns an ActiveRecord relation. There isn't an easy way to inject functionality into the resolvers
  that are used by connections (to my knowledge) - eg, by using middleware - so this helper had some GoCo-specific code
  baked into it, which probably caused odd errors about an undefined constant `GraphSupport` whenever it was used. ~~I can’t
  quite remove that functionality yet, but I did take it one step closer by having the code first check to see if the constant
  was defined, and bypass it if it’s not.~~ That code has been removed from the gem now!

- Fixed a bug where the HashCombiner would sometimes not merge hashes together (if their keys were sorted differently)

## 0.9.0
- Support for graphql version 1.2.1 and higher, but it no longer works with 0.x versions

## 0.8.0
- Updated runtime dependency requirements

## 0.7.2

### Breaking Changes
- Changed models are no longer reloaded when you call `save!` on a mutator
