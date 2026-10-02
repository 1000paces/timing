module Types
  # Milliseconds (epoch time or a duration). GraphQL Int is 32-bit, too small.
  class Millis < GraphQL::Schema::Scalar
    description "Milliseconds, as a JSON number"

    def self.coerce_input(value, _context)
      return value if value.is_a?(Integer)
      return value.to_i if value.is_a?(Float) && value == value.floor
      raise GraphQL::CoercionError, "#{value.inspect} is not a whole number of milliseconds"
    end

    def self.coerce_result(value, _context) = value&.to_i
  end
end
