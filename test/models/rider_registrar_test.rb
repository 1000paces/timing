require "test_helper"

class RiderRegistrarTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @race = create_race(event: @event)
  end

  def attrs(**over) = { first_name: "Ann", last_name: "Lee", gender: "M", ability_level: "Cat 3", license_number: "L1" }.merge(over)

  test "creates rider and registration together" do
    reg = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    assert reg.persisted?
    assert_equal "Ann Lee", reg.rider.full_name
  end

  test "reuses a rider with the same license number" do
    first = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    other_event = create_event(name: "Week 2")
    second = RiderRegistrar.register(race: create_race(event: other_event), bib: "5", rider_attrs: attrs)
    assert_equal first.rider_id, second.rider_id
  end

  test "an invalid registration leaves no orphan rider" do
    RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    assert_no_difference("Rider.count") do
      reg = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs(license_number: "L2"))
      refute reg.persisted?
      assert_includes reg.errors.full_messages, "Bib has already been taken"
    end
  end

  test "rider validation errors are reported on the registration" do
    reg = RiderRegistrar.register(race: @race, bib: "102", rider_attrs: attrs(first_name: "", license_number: nil))
    refute reg.persisted?
    assert_includes reg.errors.full_messages, "First name can't be blank"
  end

  test "same license with a different name is refused" do
    RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    other = create_race(event: create_event(name: "Week 2"))
    assert_no_difference("Registration.count") do
      reg = RiderRegistrar.register(race: other, bib: "5", rider_attrs: attrs(last_name: "Smith"))
      refute reg.persisted?
      assert_equal ["License L1 belongs to Ann Lee; check the license number"], reg.errors.full_messages
      assert_equal ["License L1 belongs to Ann Lee; check the license number"], reg.errors[:base]
    end
  end

  test "same license with a different gender is refused" do
    RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    reg = RiderRegistrar.register(race: create_race(event: create_event(name: "W2")), bib: "5", rider_attrs: attrs(gender: "F"))
    refute reg.persisted?
  end

  test "same license with name in different case or spacing reuses the rider" do
    first = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    second = RiderRegistrar.register(race: create_race(event: create_event(name: "Week 2")), bib: "5",
                                     rider_attrs: attrs(first_name: "ann", last_name: " Lee "))
    assert second.persisted?
    assert_equal first.rider_id, second.rider_id
  end
end
