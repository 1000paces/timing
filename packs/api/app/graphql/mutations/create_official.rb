module Mutations
  class CreateOfficial < BaseMutation
    argument :name, String
    argument :role, String
    argument :pin, String

    field :official, Types::OfficialType

    def resolve(name:, role:, pin:)
      require_official!("admin")
      persist(Official.new(name:, role:, pin:), :official)
    end
  end
end
