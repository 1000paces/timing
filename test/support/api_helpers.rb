module ApiHelpers
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  def sign_in(official, pin)
    post "/session", params: { name: official.name, pin: }.to_json, headers: JSON_HEADERS
  end

  def gql(query, **variables)
    post "/graphql", params: { query:, variables: }.to_json, headers: JSON_HEADERS
    JSON.parse(response.body)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiHelpers
  setup { SessionsController::RATE_LIMIT_STORE.clear }
end
