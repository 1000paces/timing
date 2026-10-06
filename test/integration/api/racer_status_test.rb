require "test_helper"

class RacerStatusTest < ActionDispatch::IntegrationTest
  SET = <<~GQL
    mutation($eventId: ID!, $bib: String!, $status: RacerStatusChange!) {
      setRacerStatus(eventId: $eventId, bib: $bib, status: $status) { errors }
    }
  GQL
  STATUS = "query($id: ID!) { standings(eventId: $id) { races { rows { bib status place } } } }"

  setup do
    @event = create_event
    race = create_race(event: @event)
    register(race:, bib: "1")
    register(race:, bib: "2", racer: create_racer(first_name: "Bo"))
  end

  def status_of(bib) = gql(STATUS, id: @event.id).dig("data", "standings", "races", 0, "rows").find { it["bib"] == bib }["status"]
  def set(bib, status) = gql(SET, eventId: @event.id, bib:, status:).dig("data", "setRacerStatus", "errors")

  test "a chief marks a racer DNF or DNS, and clears it" do
    sign_in(create_official(role: "chief", pin: "1111"), "1111")
    assert_equal [], set("1", "DNF")
    assert_equal "DNF", status_of("1")
    assert_equal [], set("1", "DNS")
    assert_equal "DNS", status_of("1")
    assert_equal [], set("1", "NONE")
    assert_equal "RACING", status_of("1")
    assert_equal %w[dnf dns revert revert], Ruling.where(event: @event).order(:created_at_ms, :id).pluck(:kind).sort
  end

  test "an unknown bib is refused, and timers can't set statuses" do
    sign_in(create_official(role: "chief", pin: "1111"), "1111")
    assert_equal ["Bib 99 is not registered in this event"], set("99", "DNF")
    sign_in(create_official(role: "timer", pin: "2222"), "2222")
    body = gql(SET, eventId: @event.id, bib: "1", status: "DNF")
    assert_equal "Requires the chief role", body["errors"].first["message"]
  end
end
