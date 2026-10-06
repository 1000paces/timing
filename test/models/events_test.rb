require "test_helper"

class EventsTest < ActiveSupport::TestCase
  test "records get UUIDv7 string ids" do
    event = create_event
    assert_match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/, event.id)
  end

  test "racing age is year difference; age on event date respects birthdays" do
    event = create_event(date: Date.new(2026, 3, 1))
    assert_equal 41, event.age_of(Date.new(1985, 6, 1))
    event.update!(age_rule: "age_on_event_date")
    assert_equal 40, event.age_of(Date.new(1985, 6, 1))
    assert_equal 41, event.age_of(Date.new(1985, 3, 1))
    assert_nil event.age_of(nil)
  end

  test "bib is unique within an event across races, but reusable across events" do
    event = create_event
    race_a = create_race(event:)
    race_b = create_race(event:, category: "Cat 4")
    register(race: race_a, bib: "101")
    dup = Registration.new(race: race_b, racer: create_racer, bib: "101")
    refute dup.valid?
    other = create_event(name: "Next week")
    assert register(race: create_race(event: other), bib: "101").persisted?
  end

  test "registration takes its event from the race and strips the bib" do
    race = create_race(event: create_event)
    reg = register(race:, bib: " 7 ")
    assert_equal race.event_id, reg.event_id
    assert_equal "7", reg.bib
  end

  test "racer license numbers are unique" do
    create_racer(license_number: "U1")
    dup = Racer.new(first_name: "A", last_name: "B", gender: "M", license_number: "U1")
    refute dup.valid?
    assert_includes dup.errors[:license_number], "has already been taken"
  end
end
