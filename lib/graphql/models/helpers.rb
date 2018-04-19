# frozen_string_literal: true

module GraphQL::Models
  module Helpers
    def self.orders_to_sql(orders)
      expressions = orders.map do |expr|
        case expr
        when Arel::Nodes::SqlLiteral
          expr.to_s
        else
          expr.to_sql
        end
      end

      expressions.join(', ')
    end

    def self.load_association_with(association, result)
      reflection = association.reflection
      association.loaded!

      if reflection.macro == :has_many
        association.target.slice!(0..-1)
        association.target.concat(result)
        result.each do |m|
          association.set_inverse_instance(m)
        end
      else
        association.target = result
        association.set_inverse_instance(result) if result
      end
    end
  end
end
