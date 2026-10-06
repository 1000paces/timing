require "test_helper"

class RacerPrivacyTest < ActionDispatch::IntegrationTest
  QUERY = <<~GQL
    query($id: ID!) { event(id: $id) { registrations { bib eligibilityWarnings racer { firstName birthDate licenseNumber } } } }
  GQL

  setup do
    @event = create_event
    race = create_race(event: @event, age_group: "Masters 40+", age_min: 40)
    register(race:, bib: "7", racer: create_racer(birth_date: Date.new(2000, 1, 1), license_number: "LIC-123"))
  end

  test "a timer sees names and bibs but not birth date, license or eligibility warnings" do
    sign_in(create_official(role: "timer", pin: "1111"), "1111")
    reg = gql(QUERY, id: @event.id).dig("data", "event", "registrations").first
    assert_equal "7", reg["bib"]
    assert_equal "Ada", reg.dig("racer", "firstName")
    assert_nil reg.dig("racer", "birthDate")
    assert_nil reg.dig("racer", "licenseNumber")
    assert_equal [], reg["eligibilityWarnings"]
  end

  test "a chief sees the real values" do
    sign_in(create_official(role: "chief", pin: "2222"), "2222")
    reg = gql(QUERY, id: @event.id).dig("data", "event", "registrations").first
    assert_equal "2000-01-01", reg.dig("racer", "birthDate")
    assert_equal "LIC-123", reg.dig("racer", "licenseNumber")
    assert reg["eligibilityWarnings"].any? { it.include?("below minimum") }
  end
end
