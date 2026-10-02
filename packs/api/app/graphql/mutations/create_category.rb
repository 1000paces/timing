module Mutations
  class CreateCategory < BaseMutation
    argument :name, String
    argument :gender, String
    argument :ability_levels, [String], required: false
    argument :age_min, Integer, required: false
    argument :age_max, Integer, required: false

    field :category, Types::CategoryType

    def resolve(**attrs)
      require_official!("admin")
      persist(Category.new({ ability_levels: [] }.merge(attrs.compact)), :category)
    end
  end
end
