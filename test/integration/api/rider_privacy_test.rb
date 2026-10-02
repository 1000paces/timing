require "test_helper"

class RiderPrivacyTest < ActionDispatch::IntegrationTest
  QUERY = <<~GQL
    query($id: ID!) { event(id: $id) { registrations { bib eligibilityWarnings rider { firstName birthDate licenseNumber } } } }
  GQL

  setup do
    @event = create_event
    race = create_race(event: @event, age_group: "Masters 40+", age_min: 40)
    register(race:, bib: "7", rider: create_rider(birth_date: Date.new(2000, 1, 1), license_number: "LIC-123"))
  end

  test "a timer sees names and bibs but not birth date, license or eligibility warnings" do
    sign_in(create_official(role: "timer", pin: "1111"), "1111")
    reg = gql(QUERY, id: @event.id).dig("data", "event", "registrations").first
    assert_equal "7", reg["bib"]
    assert_equal "Ada", reg.dig("rider", "firstName")
    assert_nil reg.dig("rider", "birthDate")
    assert_nil reg.dig("rider", "licenseNumber")
    assert_equal [], reg["eligibilityWarnings"]
  end

  test "a chief sees the real values" do
    sign_in(create_official(role: "chief", pin: "2222"), "2222")
    reg = gql(QUERY, id: @event.id).dig("data", "event", "registrations").first
    assert_equal "2000-01-01", reg.dig("rider", "birthDate")
    assert_equal "LIC-123", reg.dig("rider", "licenseNumber")
    assert reg["eligibilityWarnings"].any? { it.include?("below minimum") }
  end
end
