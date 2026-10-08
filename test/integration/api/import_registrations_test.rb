require "test_helper"

class ImportRegistrationsTest < ActionDispatch::IntegrationTest
  BIKEREG = Rails.root.join("test/fixtures/files/bikereg_export.csv").read
  ANALYZE = <<~GQL
    mutation($eventId: ID!, $csv: String!) {
      analyzeImport(eventId: $eventId, csv: $csv) { headers mapping categories { value count raceId skip } errors }
    }
  GQL
  IMPORT = <<~GQL
    mutation($eventId: ID!, $csv: String!, $mapping: JSON, $categories: JSON, $dryRun: Boolean) {
      importRegistrations(eventId: $eventId, csv: $csv, mapping: $mapping, categories: $categories, dryRun: $dryRun) {
        created updated skipped rowErrors { row message } warnings { row message } notInFile errors
      }
    }
  GQL

  setup do
    @event = create_event
    create_race(event: @event, category: nil, gender: "women", name_override: "Women Open")
    create_race(event: @event, category: "Cat 3", gender: "men")
    @masters = create_race(event: @event, category: "Masters 50+", gender: "men")
    @categories = { "Masters 50+ Men Cat 1/2/3" => { "raceId" => @masters.id }, "T-Shirt" => { "skip" => true } }
  end

  def admin! = sign_in(create_official(role: "admin", pin: "1111"), "1111")

  test "analyze returns BikeReg's mapping and categories" do
    admin!
    data = gql(ANALYZE, eventId: @event.id, csv: BIKEREG).dig("data", "analyzeImport")
    assert_equal "Category Entered / Merchandise Ordered", data.dig("mapping", "category")
    assert_equal [ "Women Open", "Cat 3 Men", "Masters 50+ Men Cat 1/2/3", "T-Shirt" ], data["categories"].map { it["value"] }
  end

  test "a dry run previews the same counts as the real import and writes nothing" do
    admin!
    preview = nil
    assert_no_difference("Registration.count") do
      preview = gql(IMPORT, eventId: @event.id, csv: BIKEREG, categories: @categories, dryRun: true).dig("data", "importRegistrations")
    end
    real = gql(IMPORT, eventId: @event.id, csv: BIKEREG, categories: @categories).dig("data", "importRegistrations")
    assert_equal [ 5, 0, 1, [] ], real.values_at("created", "updated", "skipped", "rowErrors")
    assert_equal preview.except("notInFile"), real.except("notInFile")
  end

  test "an unreadable CSV is one error" do
    admin!
    data = gql(IMPORT, eventId: @event.id, csv: "a,\"b\n1,2").dig("data", "importRegistrations")
    assert_match(/CSV could not be read/, data["errors"].first)
    assert_match(/CSV could not be read/, gql(ANALYZE, eventId: @event.id, csv: "a,\"b\n1,2").dig("data", "analyzeImport", "errors").first)
  end

  test "importing requires admin" do
    sign_in(create_official(role: "chief", pin: "2222"), "2222")
    assert_equal "Requires the admin role", gql(ANALYZE, eventId: @event.id, csv: BIKEREG)["errors"].first["message"]
    assert_equal "Requires the admin role", gql(IMPORT, eventId: @event.id, csv: BIKEREG)["errors"].first["message"]
  end
end
