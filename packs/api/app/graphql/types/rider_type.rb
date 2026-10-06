module Types
  class RiderType < BaseObject
    field :id, ID, null: false
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :gender, String, null: false
    field :birth_date, GraphQL::Types::ISO8601Date
    field :license_number, String
    field :team, String

    # Spec §8: timers are capture-only; PII resolves to null for them.
    def birth_date = chief? ? object.birth_date : nil
    def license_number = chief? ? object.license_number : nil

    private

    def chief? = context[:current_official]&.at_least?("chief") || false
  end
end
