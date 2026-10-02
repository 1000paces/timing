module Types
  class RiderType < BaseObject
    field :id, ID, null: false
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :gender, String, null: false
    field :birth_date, GraphQL::Types::ISO8601Date
    field :ability_level, String
    field :license_number, String
    field :team, String
  end
end
