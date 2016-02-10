# This is a helper class. It lets you build simple DSL's. Methods called against the class are
# converted into attributes in a hash.
module GraphQL
  module Models
    class Definer
      def initialize(*methods)
        @values = {}
        methods.each do |m|
          define_singleton_method(m) do |*args|
            if args.blank?
              @values[m] = nil
            elsif args.length == 1
              @values[m] = args[0]
            else
              @values[m] = args
            end
          end
        end
      end

      def defined_values
        @values
      end
    end
  end
end
