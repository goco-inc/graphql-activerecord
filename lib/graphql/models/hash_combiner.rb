# frozen_string_literal: true

module GraphQL::Models::HashCombiner
  class << self
    # Takes a set of hashes that represent conditions, and combines them into the smallest number of hashes
    def combine(hashes)
      # Group the hashes by keys. If they are querying different columns, they can't be combined
      by_keys = hashes.group_by { |h| h.keys.sort }
      by_keys.map { |keys, values| combine_core(values, keys) }.flatten
    end

    private

    def combine_core(hashes, keys)
      return [] if keys.nil? || keys.empty?

      # If there's only one key in each of the hashes, then combine that into a single hash with an array
      if keys.length == 1
        values = hashes.map { |h| h[keys[0]] }
        return [{ keys[0] => values.flatten.uniq }]
      end

      # Get the most commonly occuring value in the hash, and remove it from the keys.
      # Return one hash for each unique value.
      min_key = keys.min_by { |k| hashes.map { |h| h[k] }.flatten.uniq.count }
      inner_keys = keys.dup
      inner_keys.delete(min_key)

      # Group the hashes based on the value that they have for that key
      grouped = hashes.group_by { |h| h[min_key] }

      grouped = grouped.map do |key_value, inner_hashes|
        combined = combine_core(inner_hashes, inner_keys)
        merge_with = { min_key => key_value }

        combined.map { |reduced_hash| merge_with.merge(reduced_hash) }
      end

      grouped.flatten
    end
  end
end
