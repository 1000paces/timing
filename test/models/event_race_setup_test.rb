require "test_helper"

class EventRaceSetupTest < ActiveSupport::TestCase
  SIX_PM = 1_791_000_000_000

  test "discipline is required and sub-disciplines must belong to it" do
    assert Event.new(name: "x", date: Date.current, discipline: "mountain_bike", sub_discipline: "xcc").valid?
    assert Event.new(name: "x", date: Date.current, discipline: "cyclocross").valid?
    refute Event.new(name: "x", date: Date.current, discipline: "road", sub_discipline: "xcc").valid?
    refute Event.new(name: "x", date: Date.current, discipline: "bmx").valid?
    refute Event.new(name: "x", date: Date.current, discipline: nil).valid?
  end

  test "finish with leader defaults from the discipline when not given" do
    on = ->(discipline, sub = nil) { create_event(discipline:, sub_discipline: sub).finish_with_leader }
    assert on.("cyclocross")
    assert on.("mountain_bike", "xcc")
    refute on.("mountain_bike", "xco")
    assert on.("road", "criterium")
    refute on.("road", "road_race")
    refute on.("gravel")
    refute on.("run")
    refute create_event(discipline: "cyclocross", finish_with_leader: false).finish_with_leader
  end

  test "default race name joins category, age group and gender; an override wins" do
    event = create_event
    assert_equal "Cat 3 Masters 35+ Men", create_race(event:, category: "Cat 3", age_group: "Masters 35+", gender: "men").name
    assert_equal "Novice Women", create_race(event:, category: "Novice", age_group: nil, gender: "women").name
    assert_equal "Open", create_race(event:, category: nil, age_group: nil, gender: "open").name
    race = create_race(event:, category: "Pro", gender: "women", name_override: "Elite Women")
    assert_equal "Elite Women", race.name
    assert_equal "Pro Women", race.default_name
  end

  # Review Focus 2
  test "race names are unique within an event, ignoring case" do
    event = create_event
    create_race(event:, category: "Cat 3", gender: "men")
    dup = Race.new(event:, category: nil, gender: "men", name_override: "cat 3 men", scheduled_at_ms: SIX_PM)
    refute dup.valid?
    assert_includes dup.errors.full_messages, "Name cat 3 men is already used in this event"
    assert create_race(event: create_event(name: "Other"), category: "Cat 3", gender: "men").persisted?
  end

  test "gender and scheduled start are required; laps positive; ages ordered" do
    event = create_event
    refute Race.new(event:, gender: "M", scheduled_at_ms: SIX_PM).valid?
    refute Race.new(event:, gender: "men").valid?
    refute Race.new(event:, gender: "men", scheduled_at_ms: SIX_PM, expected_laps: 0).valid?
    refute Race.new(event:, gender: "men", scheduled_at_ms: SIX_PM, age_min: 50, age_max: 40).valid?
  end

  test "finish with leader is inherited unless the race overrides it" do
    event = create_event(discipline: "cyclocross")
    assert create_race(event:).effective_finish_with_leader
    refute create_race(event:, category: "Novice", finish_with_leader: false).effective_finish_with_leader
  end

  test "a cohort is the finish-with-leader races sharing a scheduled start" do
    event = create_event(discipline: "cyclocross")
    a = create_race(event:, category: "A", scheduled_at_ms: SIX_PM)
    b = create_race(event:, category: "B", scheduled_at_ms: SIX_PM)
    alone = create_race(event:, category: "C", scheduled_at_ms: SIX_PM, finish_with_leader: false)
    later = create_race(event:, category: "D", scheduled_at_ms: SIX_PM + 3_600_000)
    assert_equal [a, b].sort_by(&:id), a.cohort.sort_by(&:id)
    assert_equal [alone], alone.cohort
    assert_equal [later], later.cohort
  end

  test "eligibility checks gender and age only" do
    event = create_event(date: Date.new(2026, 10, 18))
    race = create_race(event:, category: "Cat 3", age_group: "Masters 35+", age_min: 35, gender: "men")
    rider = ->(**attrs) { Rider.new({ first_name: "A", last_name: "B", gender: "M", birth_date: Date.new(1980, 1, 1) }.merge(attrs)) }
    assert_empty Eligibility.warnings(rider: rider.(), race:, event:)
    assert_match(/gender F/, Eligibility.warnings(rider: rider.(gender: "F"), race:, event:).first)
    assert_match(/below minimum 35/, Eligibility.warnings(rider: rider.(birth_date: Date.new(2000, 1, 1)), race:, event:).first)
    open_race = create_race(event:, category: "Novice", gender: "open")
    assert_empty Eligibility.warnings(rider: rider.(gender: "X"), race: open_race, event:)
  end
end
