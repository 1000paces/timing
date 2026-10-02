class TimingSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType
  max_depth 12

  rescue_from(ActiveRecord::RecordNotFound) { raise GraphQL::ExecutionError, "Not found" }
end
