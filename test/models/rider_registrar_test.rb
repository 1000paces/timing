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
end
