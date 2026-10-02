class TimingSchema < GraphQL::Schema
  query Types::QueryType

  rescue_from(ActiveRecord::RecordNotFound) { raise GraphQL::ExecutionError, "Not found" }
end
