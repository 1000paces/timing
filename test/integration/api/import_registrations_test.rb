require "test_helper"

class ImportRegistrationsTest < ActionDispatch::IntegrationTest
  test "admin imports registrations over GraphQL" do
    sign_in(create_official(role: "admin", pin: "1111"), "1111")
    event = create_event
    create_race(event:, category: nil, gender: "women", name_override: "Women Open")
    csv = "first_name,last_name,gender,bib,race\nAnn,Lee,F,301,Women Open\nBea,Kim,F,301,Women Open\n"
    body = gql(<<~GQL, eventId: event.id, csv:)
      mutation($eventId: ID!, $csv: String!) {
        importRegistrations(eventId: $eventId, csv: $csv) { created rowErrors { row message } warnings { row message } errors }
      }
    GQL
    data = body.dig("data", "importRegistrations")
    assert_equal 1, data["created"]
    assert_equal [{ "row" => 3, "message" => "Bib has already been taken" }], data["rowErrors"]
  end
end
