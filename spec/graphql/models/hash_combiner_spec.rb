require 'spec_helper'

RSpec.describe GraphQL::Models::HashCombiner do
  describe '::combine' do
    it "groups items based on the most common value first" do
      input = [
        { type: 'hello', id: 1 },
        { type: 'hello', id: 2 },
        { type: 'hello', id: 3 },
        { type: 'hello', id: 4 },
        { type: 'world', id: 11 },
        { type: 'world', id: 21 },
        { type: 'world', id: 31 },
        { type: 'world', id: 41 },
      ]

      output = [
        { type: 'hello', id: [1, 2, 3, 4] },
        { type: 'world', id: [11, 21, 31, 41] }
      ]

      expect(GraphQL::Models::HashCombiner.combine(input)).to eq output
    end

    it "doesn't generate a separate group if all hashes have the same value for two keys" do
      input = [
        { prop_1: 'hello', prop_2: 'world', id: 1 },
        { prop_1: 'hello', prop_2: 'world', id: 2 },
        { prop_1: 'hello', prop_2: 'world', id: 3 },
        { prop_1: 'hello', prop_2: 'world', id: 4 },
      ]

      output = [
        { prop_1: 'hello', prop_2: 'world', id: [1, 2, 3, 4] }
      ]

      expect(GraphQL::Models::HashCombiner.combine(input)).to eq output
    end
  end
end
