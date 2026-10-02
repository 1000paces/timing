module Mutations
  class ImportRegistrations < BaseMutation
    argument :event_id, ID
    argument :csv, String
    argument :mapping, GraphQL::Types::JSON, required: false, description: "field name => CSV header"

    field :created, Integer, null: false
    field :row_errors, [Types::RowMessageType], null: false
    field :warnings, [Types::RowMessageType], null: false

    def resolve(event_id:, csv:, mapping: {})
      require_official!("admin")
      result = RegistrationImport.call(event: Event.find(event_id), csv:, mapping:)
      { created: result.created, row_errors: result.errors, warnings: result.warnings, errors: [] }
    rescue CSV::MalformedCSVError => e
      { created: 0, row_errors: [], warnings: [], errors: ["CSV could not be read: #{e.message}"] }
    end
  end
end
