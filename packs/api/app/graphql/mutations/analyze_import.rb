module Mutations
  class AnalyzeImport < BaseMutation
    description "Read a registration CSV: its headers, the suggested column mapping, and each category with its row count"
    argument :event_id, ID
    argument :csv, String

    field :headers, [ String ], null: false
    field :mapping, GraphQL::Types::JSON, null: false, description: "field name => CSV header"
    field :categories, [ Types::ImportCategoryType ], null: false

    def resolve(event_id:, csv:)
      require_official!("admin")
      analysis = RegistrationImport.analyze(event: Event.find(event_id), csv:)
      { headers: analysis.headers, mapping: analysis.mapping, categories: analysis.categories, errors: [] }
    rescue CSV::MalformedCSVError => e
      { headers: [], mapping: {}, categories: [], errors: [ "CSV could not be read: #{e.message}" ] }
    end
  end
end
