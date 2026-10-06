require "test_helper"

class RegistrationModelTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @race = create_race(event: @event)
  end

  test "a bib is optional, but unique in the event when present" do
    a = register(race: @race, bib: nil)
    b = register(race: @race, bib: "")
    assert_nil a.bib
    assert_nil b.bib
    register(race: @race, bib: "7")
    dup = Registration.new(race: @race, racer: create_racer, bib: "7")
    refute dup.valid?
    assert_includes dup.errors.full_messages, "Bib has already been taken"
  end

  test "source, age, external category and check-in" do
    reg = Registration.create!(race: @race, racer: create_racer, bib: "1", age: 41, source: "import", external_category: "Cat 3 Men")
    assert_equal [41, "import", "Cat 3 Men"], [reg.age, reg.source, reg.external_category]
    refute reg.checked_in?
    reg.update!(checked_in_at_ms: 5)
    assert reg.checked_in?
    assert_equal "manual", Registration.create!(race: @race, racer: create_racer).source
    refute Registration.new(race: @race, racer: create_racer, source: "web").valid?
  end

  test "racers have city and state; ability level is gone" do
    racer = create_racer(city: "Boulder", state: "CO")
    assert_equal %w[Boulder CO], [racer.city, racer.state]
    refute Racer.column_names.include?("ability_level")
  end

  test "bib ranges: ordered, positive, and not overlapping within the event" do
    @race.update!(bib_from: 100, bib_to: 199)
    assert_equal 100..199, @race.bib_range
    backwards = create_race(event: @event, category: "Cat 4")
    refute backwards.update(bib_from: 50, bib_to: 10)
    assert_includes backwards.errors.full_messages, "Bib to must be greater than or equal to bib from"
    refute backwards.update(bib_from: 0, bib_to: 10)

    other = create_race(event: @event, category: "Cat 5")
    refute other.update(bib_from: 150, bib_to: 249)
    assert_includes other.errors.full_messages, "Bib range 150–249 overlaps Cat 3 Men (100–199)"

    refute @event.update(bib_from: 190, bib_to: 299)
    assert_includes @event.errors.full_messages, "Bib range 190–299 overlaps Cat 3 Men (100–199)"
    assert @event.update(bib_from: 200, bib_to: 299)
    refute other.update(bib_from: 250, bib_to: 260)
    assert_includes other.errors.full_messages, "Bib range 250–260 overlaps the event range (200–299)"
  end

  test "a race without its own range uses the event's" do
    @event.update!(bib_from: 1, bib_to: 99)
    assert_equal 1..99, @race.reload.bib_range
    @race.update!(bib_from: 100, bib_to: 110)
    assert_equal 100..110, @race.bib_range
  end

  test "category mappings: one per category, a race or skip" do
    CategoryMapping.create!(event: @event, external_category: "Cat 3 Men", race: @race)
    CategoryMapping.create!(event: @event, external_category: "T-Shirt", skip: true)
    refute CategoryMapping.new(event: @event, external_category: "T-Shirt", skip: true).valid?
    refute CategoryMapping.new(event: @event, external_category: "Nothing").valid?
  end

  test "eligibility uses the registration's age when the birth date is unknown" do
    masters = create_race(event: @event, category: "Masters", age_min: 35)
    racer = create_racer(birth_date: nil)
    assert_match(/below minimum 35/, Registration.create!(race: masters, racer:, age: 30).eligibility_warnings.first)
    assert_empty Registration.create!(race: masters, racer: create_racer(birth_date: nil), age: 40).eligibility_warnings
  end

  test "a checked-in racer's bib is locked once set" do
    reg = register(race: @race, bib: nil)
    reg.check_in!(at_ms: 1)
    assert reg.update(bib: "5"), "a checked-in racer without a bib can be given one"
    refute reg.update(bib: "6")
    assert_includes reg.errors.full_messages, "Bib can't change once the racer is checked in (undo check-in first)"
    reg.reload.undo_check_in!
    assert reg.update(bib: "6")
  end
end
