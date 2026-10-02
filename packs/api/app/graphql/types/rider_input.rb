module Types
  class RiderInput < BaseInputObject
    argument :first_name, String
    argument :last_name, String
    argument :gender, String
    argument :birth_date, GraphQL::Types::ISO8601Date, required: false
    argument :ability_level, String, required: false
    argument :license_number, String, required: false
    argument :team, String, required: false
  end
end
