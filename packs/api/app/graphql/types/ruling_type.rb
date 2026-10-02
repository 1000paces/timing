module Types
  class RulingType < BaseObject
    field :id, ID, null: false
    field :kind, String, null: false
    field :payload, GraphQL::Types::JSON, null: false
    field :reason, String
    field :created_at_ms, Millis, null: false
    field :official_name, String
    field :reverted, Boolean, null: false

    def official_name = object.official_id && Official.find_by(id: object.official_id)&.name
    def reverted = context.fetch(:cancelled_ruling_ids, Set.new).include?(object.id)
  end
end
