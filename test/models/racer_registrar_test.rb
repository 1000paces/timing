require "test_helper"

class RacerRegistrarTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @race = create_race(event: @event)
  end

  def attrs(**over) = { first_name: "Ann", last_name: "Lee", gender: "M", license_number: "L1" }.merge(over)

  test "creates racer and registration together" do
    reg = RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs)
    assert reg.persisted?
    assert_equal "Ann Lee", reg.racer.full_name
  end

  test "reuses a racer with the same license number" do
    first = RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs)
    other_event = create_event(name: "Week 2")
    second = RacerRegistrar.register(race: create_race(event: other_event), bib: "5", racer_attrs: attrs)
    assert_equal first.racer_id, second.racer_id
  end

  test "an invalid registration leaves no orphan racer" do
    RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs)
    assert_no_difference("Racer.count") do
      reg = RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs(license_number: "L2"))
      refute reg.persisted?
      assert_includes reg.errors.full_messages, "Bib has already been taken"
    end
  end

  test "racer validation errors are reported on the registration" do
    reg = RacerRegistrar.register(race: @race, bib: "102", racer_attrs: attrs(first_name: "", license_number: nil))
    refute reg.persisted?
    assert_includes reg.errors.full_messages, "First name can't be blank"
  end

  test "same license with a different name is refused" do
    RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs)
    other = create_race(event: create_event(name: "Week 2"))
    assert_no_difference("Registration.count") do
      reg = RacerRegistrar.register(race: other, bib: "5", racer_attrs: attrs(last_name: "Smith"))
      refute reg.persisted?
      assert_equal ["License L1 belongs to Ann Lee; check the license number"], reg.errors.full_messages
      assert_equal ["License L1 belongs to Ann Lee; check the license number"], reg.errors[:base]
    end
  end

  test "same license with a different gender is refused" do
    RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs)
    reg = RacerRegistrar.register(race: create_race(event: create_event(name: "W2")), bib: "5", racer_attrs: attrs(gender: "F"))
    refute reg.persisted?
  end

  test "same license with name in different case or spacing reuses the racer" do
    first = RacerRegistrar.register(race: @race, bib: "101", racer_attrs: attrs)
    second = RacerRegistrar.register(race: create_race(event: create_event(name: "Week 2")), bib: "5",
                                     racer_attrs: attrs(first_name: "ann", last_name: " Lee "))
    assert second.persisted?
    assert_equal first.racer_id, second.racer_id
  end

  test "walk-ups are manual and may have no bib" do
    reg = RacerRegistrar.register(race: @race, bib: nil, racer_attrs: attrs)
    assert reg.persisted?
    assert_equal ["manual", nil], [reg.source, reg.bib]
  end

  test "upsert matches by license, else by name within the event, and never clears a bib" do
    first = RacerRegistrar.upsert(event: @event, race: @race, attrs: attrs(bib: "7", team: "A"), source: "import")
    assert first.previously_new_record?
    by_license = RacerRegistrar.upsert(event: @event, race: @race, attrs: attrs(bib: nil, team: "B"), source: "import")
    assert_equal first.id, by_license.id
    assert_equal ["7", "B"], [by_license.bib, by_license.racer.team]
    by_name = RacerRegistrar.upsert(event: @event, race: @race, attrs: attrs(license_number: nil, first_name: "ANN", team: "C"), source: "import")
    assert_equal first.id, by_name.id
    assert_equal "C", by_name.racer.team
  end
end
