module Mutations
  class BaseMutation < GraphQL::Schema::Mutation
    include Authorization

    field :errors, [ String ], null: false

    private

    def persist(record, key)
      record.save ? { key => record, errors: [] } : { key => nil, errors: record.errors.full_messages }
    end
  end
end
