module Types
  class RiderInput < BaseInputObject
    argument :first_name, String
    argument :last_name, String
    argument :gender, String
    argument :birth_date, GraphQL::Types::ISO8601Date, required: false
    argument :license_number, String, required: false
    argument :team, String, required: false
    argument :city, String, required: false
    argument :state, String, required: false
  end
end
