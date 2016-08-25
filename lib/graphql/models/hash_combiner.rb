module GraphQL::Models::HashCombiner
  class << self
    # Takes a set of hashes that represent conditions, and combines them into the smallest number of hashes
    def combine(hashes)
      # Group the hashes by keys. If they are querying different columns, they can't be combined

    end
  end
end
