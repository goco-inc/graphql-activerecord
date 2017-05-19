# GraphQL::Models

This gem is designed to help you map Active Record models to GraphQL types, both for queries and mutations, using the [`graphql`](https://github.com/rmosolgo/graphql-ruby)
gem. It assumes that you're using Rails and have `graphql-batch` set up.

It extends the `define` methods for GraphQL object types to provide a simple syntax for adding fields that access attributes
on your model. It also makes it easy to "flatten" models together across associations, or to create fields that just access
the association as a separate object type.

In the process, this gem also converts `snake_case` attribute names into `camelCase` field names. When you go to build a mutation using this gem, it knows how to revert that process, even in cases where the conversion isn't symmetric.

Here's an example:
```ruby
EmployeeGraph = GraphQL::ObjectType.define do
  name "Employee"

  # Looks for an Active Record model called "Employee"
  backed_by_model :employee do

    # The gem will look at the data type for the attributes, and map them to GraphQL types
    attr :title
    attr :salary

    # You can flatten fields across associations to simplify the schema. In this example, an
    # Employee belongs to a Person.
    proxy_to :person do
      # These fields get converted to camel case (ie, firstName, lastName) on the schema
      attr :first_name
      attr :last_name
      attr :email

      # You can also provide the association itself as an object field. In this example, a
      # Person has one Address. The gem assumes that the corresponding GraphQL object type
      # is called "AddressType" (but you can override, see installation section below).
      has_one :address
    end
  end
end
```

You can also build a corresponding mutation, using a very similar syntax. Mutations are more complicated, since they involve
not just changing the data, but also validating it. Here's an example:
```ruby
UpdateEmployeeMutation = GraphQL::Relay::Mutation.define do
  name "UpdateEmployee"

  input_field :id, !types.ID

  # For mutations, you create a mutator definition. This will add the input fields to your
  # mutation, and also return an object that you'll use in the resolver to perform the mutation.
  # The parameters you pass are explained below.
  mutator_definition = GraphQL::Models.define_mutator(self, Employee, null_behavior: :leave_unchanged) do
    attr :title
    attr :salary

    proxy_to :person do
      attr :first_name
      attr :last_name
      attr :email

      # You can use nested input object types to allow making changes across associations with a single mutation.
      # Unlike querying, you need to be explicit about what fields on associated objects can be changed.
      nested :address, null_behavior: :set_null do
        attr :line_1
        attr :line_2
        attr :city
        attr :state
        attr :postal_code  
      end
    end
  end

  return_field :employee, EmployeeGraph

  resolve -> (inputs, context) {
    # Fetch (or create) the model that the mutation should change
    model = Employee.find(inputs[:id])

    # Get the mutator
    mutator = mutator_definition.mutator(model, inputs, context)

    # Call `apply_changes` to update the models. This does not save the changes to the database yet:
    mutator.apply_changes

    # Let's validate the changes. This will raise an exception that can be caught in middleware:
    mutator.validate!

    # Verify that the user is allowed to make the changes. Explained below:
    mutator.authorize!

    # If that passes, let's save the changes and return the result
    mutator.save!

    { employee: model }
  }
end
```

## Installation

To get started, you should add this line to your application's Gemfile:

```ruby
gem 'graphql-activerecord'
```

And then execute:

    $ bundle install

Next, you need to supply a few callbacks. I put these inside of `config/initializers` in my Rails app:
```ruby
# This proc takes a Relay global ID, and returns the Active Record model. It can be the same as
# the `object_to_id` proc that you use for global node identification:
GraphQL::Models.model_from_id = -> (id, context) {
  model_type, model_id = NodeHelpers.decode_id(id)
  model_type.find(model_id)
}

# This proc essentially reverses that process:
GraphQL::Models.id_for_model = -> (model_type_name, model_id) {
  NodeHelpers.encode_id(model_type_name, model_id)
}

# This proc is used when you're authorizing changes to a model inside of a mutator:
GraphQL::Models.authorize = -> (context, action, model) {
  # Action will be either :create, :update, or :destroy
  # Raise an exception if the action should not proceed
  user = context['user']
  model.authorize_changes!(action, user)
}

# The gem assumes that if your model is called `MyModel`, the corresponding type is `MyModelType`.
# You can override that convention. Return `nil` if the model doesn't have a GraphQL type:
GraphQL::Models.model_to_graphql_type -> (model_class) { "#{model_class.name}Graph".safe_constantize }
```

Finally, you need to set a few options on your schema:
```ruby
GraphQL::Schema.define do
  # Set up the graphql-batch gem
  lazy_resolve(Promise, :sync)
  instrument(:query, GraphQL::Batch::Setup)

  # Set up the graphql-activerecord gem
  instrument(:field, GraphQL::Models::Instrumentation.new)
end
```

### Database compatibility

This gem uses `graphql-batch` to optimize loading associated models in your graph, so that you don't end up with lots of N+1
queries. It tries to do that in a way that preserves things like scopes that change the order or filter the rows retrieved.

Unfortunately, that means that it needs to build some custom SQL expressions, and they might not be compatible with every
database engine. They should work correctly on PostgreSQL. For other databases, your mileage may vary.

### Global ID's

When you use the `has_one` or `has_many_array` helpers to output associations, the gem will also include a field that only
returns the global ID's of the models. To do that, it calls a method named `gid` on the model. You'll need to provide that method for those fields to work. We do that by adding it to our `ApplicationRecord` base class:

```ruby
class ApplicationRecord < ActiveRecord::Base
  def gid
    # add code to return a global object ID here
  end
end
```

## Usage

Inside of your GraphQL object types, you use `backed_by_model` to create fields that are tied to your models (see
example above). Inside of those blocks, you have some helper methods.

### Attribute helpers

You use the `attr` method to add an ordinary attribute from your model to your schema:
```ruby
backed_by_model :employee do
  attr :first_name
  attr :last_name
end
```

The gem knows how to handle basic attribute types: boolean, int, float, and string. For other types, you need
to tell it what GraphQL type to use:

```ruby
# config/initializers/graphql_activerecord.rb
GraphQL::Models::DatabaseTypes.register(:decimal, DecimalType)

# You can wrap the type in a proc, or use a string, so that you don't break code reloading:
GraphQL::Models::DatabaseTypes.register(:decimal, -> { DecimalType })
GraphQL::Models::DatabaseTypes.register(:decimal, "DecimalType")

# If you're not using a scalar, you need to give it separate input/output types:
GraphQL::Models::DatabaseTypes.register(:date, DateType, DateInputType)
```

#### Nullability of attributes
The gem will mark a field as non-nullable if:
- the database column is non-null
- the attribute has an unconditional presence validator on it

There are two ways you can override this behavior:
- You can pass either `nullable: true` or `nullable: false` to the helper, and no automatic detection happens
- You can disable null detection for the entire `backed_by_model` block

Example:
```ruby
backed_by_model :employee do
  # All fields created by the gem will be nullable
  detect_nulls false

  # Override it on a per-field basis
  attr :first_name, nullable: false
end
```

If you use a `proxy_to` block, the gem will automatically detect whether the associated model
has a presence validator on it. If it doesn’t, all fields inside of the block are nullable:

```ruby
backed_by_model :employee do

  # If you have `validates :person, presence: true` in your model, then nullability
  # on these fields is preserved. Otherwise, they will all be nullable.
  proxy_to :person do
    attr :birthday
  end
end
```

### Association helpers
There are three helpers that you can use to build fields for associated models:

- `has_one` can be used for either `belongs_to` or `has_one` associations
- `has_many_array` will return all of the associated models as a GraphQL list
- `has_many_connection` will return a paged connection of the associated models

#### Nullability of associations
When you use the `has_one` helper, the gem follows the same rules for nullability as it does for attributes. Thus,
it’ll check for a presence validator on the association itself:

```ruby
class MyModel < ApplicationRecord
  belongs_to :some_other_model
  validates :some_other_model, presence: true
end
```

In addition, for `belongs_to` models, it’ll check the nullability of the foreign key:
```ruby
class MyModel < ApplicationRecord
  belongs_to :some_other_model
  validates :some_other_model_id, presence: true
end
```

For `has_many` associations, it does not check for presence validators; rather, it assumes that an empty array
will be returned if there are no associated models, so the field is always marked non-null (but subject to the same rules
as attributes regarding proxy blocks).

### Fields inside of `proxy_to` blocks
You can also define ordinary fields inside of `proxy_to` blocks. When you do that, your field will receive the associated model
as the object, instead of the original model. This is meant to allow you to take advantage of the optimized association loading
that the gem provides:

```ruby
backed_by_model :employee do
  proxy_to :person do
    field :someCustomField, types.Int do
      resolve -> (model, args, context) {
        # model is an instance of Person, not Employee
      }
    end
  end
end
```

### GraphQL Enum's

Active Record allows you to define enum fields on your models. They're stored as integers, but treated as strings in your app.
You can use a helper to automatically build GraphQL enum types for them:

```ruby
class MyModel < ApplicationRecord
  enum status: [:active, :inactive]
  graphql_enum :status
end

# You can access the auto-built type if you need to:
MyModel.graphql_enum_types[:status]

# When you use it inside of your GraphQL schema, it'll know to use the GraphQL enum type:
MyModelGraph = GraphQL::ObjectType.define do
  backed_by_model :my_model do
    attr :status
  end
end
```

You can also manually specify the type to use, if you just want the type mapping behavior:
```ruby
  graphql_enum :status, type: StatusEnum
```

### Defining Mutations

When you define a mutation, there are a few parameters that you need to pass. Here's an example:

```ruby
mutator_definition = GraphQL::Models.define_mutator(self, Employee, null_behavior: :leave_unchanged)
```

The parameters are:
- The definer object: it needs this so that it can create the input fields. You should always pass `self` for this parameter.
- The model class that the mutator is changing: it needs this so that it can map attributes to the correct input types.
- `null_behavior`: this lets you choose how null values are treated. It's explained below.

#### Virtual Attributes
In your mutator, you can specify virtual attributes on your model, you just need to provide the type:
```ruby
attr :some_fake_attribute, type: types.String
```

#### null_behavior

When you build a mutation, you have two options that control how null values are treated. They are meant to allow you
to choose behavior similar to HTTP PATCH or HTTP POST, where you may want to update just part of a model without having to supply
values for every field.

You specify which option you'd like using the `null_behavior` parameter when defining the mutation:
- `leave_unchanged` means that if the input field contains a null value, it is ignored
- `set_null` means that if the input field contains a null value, the attribute will actually be set to `nil`

##### set_null
The `set_null` option is the simpler of the two, and you should probably default to using that option. When you pick this option,
null values behave as you would expect: they cause the attribute to be set to `nil`.

But another important side-effect is that the input fields on the mutation will be marked as non-nullable if the underlying
database column is not nullable, or if there is an unconditional presence validator on that field.

##### leave_unchanged
If you select this option, any input fields that contain null values will be ignored. Instead, if you really do want to set a
field to null, the gem adds a field called `unsetFields`. It takes an array of field names, and it will set all of those fields
to null.

If the field is not nullable in the database, or it has an unconditional presence validator, you cannot pass it to `unsetFields`.
Also, if _all_ of the fields meet this criteria, the gem does not even create the `unsetFields` field.

The important side-effect here is that `leave_unchanged` causes all of the input fields on the mutation to be nullable.

### Mutations and has_many associations
You can create mutations that update models across a `has_many` association, by using a `nested` block just like you would for
`has_one` or `belongs_to` associations:

```ruby
nested :emergency_contacts, null_behavior: :set_null do
  attr :first_name
  attr :last_name
  attr :phone
end
```

By default, inputs are matched to associated models by position (ie, the first input to the first model, etc). However, if you
have an attribute that should instead be used to match them, you can specify it:
```ruby
nested :emergency_contacts, find_by: :priority, null_behavior: :set_null do
  attr :first_name
  attr :last_name
  attr :phone
end
```

This causes the gem to automatically include `priority` as an input field. You could also manually specify the
`priority` field if you wanted to override its name or type.

Also, an important note is that the gem assumes that you are passing up _all_ of the associated models, and not just some of
them. It will destroy extra models, or create missing models.

### Other things that need to be documented
- Custom scalar types
- `object_to_model`
- Retrieving field metadata (for building an authorization middleware)
- Validation error exceptions


## Development

TODO: Write development instructions here 😬

Current goals:
- RSpec tests. Requires getting a dummy schema in place.
- Clean up awkward integration points (ie, global node identification)
- Deprecate and remove relation loader code
- Compatibility with latest version of `graphql` gem

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/graphql-activerecord. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
