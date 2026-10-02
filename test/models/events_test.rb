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

  test "start group finish rule must be fixed_laps or timed with positive values" do
    event = create_event
    assert StartGroup.new(event:, name: "a", finish_rule: { type: "fixed_laps", laps: 5 }).valid?
    assert StartGroup.new(event:, name: "a", finish_rule: { type: "timed", target_duration_ms: 2_700_000 }).valid?
    refute StartGroup.new(event:, name: "a", finish_rule: { type: "fixed_laps", laps: 0 }).valid?
    refute StartGroup.new(event:, name: "a", finish_rule: { type: "sprint" }).valid?
    refute StartGroup.new(event:, name: "a", finish_rule: nil).valid?
  end

  test "finish rule keys are stored as strings" do
    group = create_start_group(event: create_event, finish_rule: { type: "fixed_laps", laps: 4 })
    assert_equal({ "type" => "fixed_laps", "laps" => 4 }, group.reload.finish_rule)
  end

  test "race start group must belong to the same event" do
    other_group = create_start_group(event: create_event(name: "Other"))
    race = Race.new(event: create_event, category: create_category, start_group: other_group)
    refute race.valid?
    assert_includes race.errors[:start_group], "must belong to the same event"
  end

  test "category age range must be ordered" do
    refute Category.new(name: "x", gender: "M", age_min: 50, age_max: 40).valid?
    assert Category.new(name: "x", gender: "open", age_min: 35).valid?
  end

  test "bib is unique within an event across races, but reusable across events" do
    event = create_event
    group = create_start_group(event:)
    race_a = create_race(event:, start_group: group)
    race_b = create_race(event:, start_group: group, category: create_category(name: "Cat 4"))
    register(race: race_a, bib: "101")
    dup = Registration.new(race: race_b, rider: create_rider, bib: "101")
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

  test "rider license numbers are unique" do
    create_rider(license_number: "U1")
    dup = Rider.new(first_name: "A", last_name: "B", gender: "M", license_number: "U1")
    refute dup.valid?
    assert_includes dup.errors[:license_number], "has already been taken"
  end
end
