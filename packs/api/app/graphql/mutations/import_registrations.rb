module Mutations
  class ImportRegistrations < BaseMutation
    description "Import registrations; re-imports update matching riders and never remove anyone"
    argument :event_id, ID
    argument :csv, String
    argument :mapping, GraphQL::Types::JSON, required: false, description: "field name => CSV header; omitted fields use the suggested mapping"
    argument :categories, GraphQL::Types::JSON, required: false,
                          description: "category value => { raceId } or { skip: true }; others use the saved choice or a race of the same name"
    argument :dry_run, Boolean, required: false, default_value: false, description: "Report what would happen without changing anything"

    field :created, Integer, null: false
    field :updated, Integer, null: false
    field :skipped, Integer, null: false, description: "Rows whose category is skipped (merchandise)"
    field :row_errors, [Types::RowMessageType], null: false
    field :warnings, [Types::RowMessageType], null: false
    field :not_in_file, [String], null: false, description: "Imported earlier but missing from this file; never removed"

    def resolve(event_id:, csv:, mapping: {}, categories: {}, dry_run: false)
      require_official!("admin")
      choices = categories.to_h.transform_values { |c| { "race_id" => c["raceId"], "skip" => c["skip"] == true } }
      result = RegistrationImport.call(event: Event.find(event_id), csv:, mapping:, categories: choices, dry_run:)
      { created: result.created, updated: result.updated, skipped: result.skipped, row_errors: result.errors,
        warnings: result.warnings, not_in_file: result.not_in_file, errors: [] }
    rescue CSV::MalformedCSVError => e
      { created: 0, updated: 0, skipped: 0, row_errors: [], warnings: [], not_in_file: [], errors: ["CSV could not be read: #{e.message}"] }
    end
  end
end
