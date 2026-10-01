require "test_helper"

class EligibilityTest < ActiveSupport::TestCase
  setup { @event = create_event(date: Date.new(2026, 10, 18)) }

  def warnings(rider_attrs = {}, category_attrs = {})
    Eligibility.warnings(rider: Rider.new({ first_name: "A", last_name: "B", gender: "M", birth_date: Date.new(1980, 1, 1), ability_level: "Cat 3" }.merge(rider_attrs)),
                         category: Category.new({ name: "C", gender: "M", ability_levels: ["Cat 3"], age_min: 35, age_max: 49 }.merge(category_attrs)),
                         event: @event)
  end

  test "eligible rider has no warnings" do
    assert_empty warnings
  end

  test "warns on gender, ability, and age mismatches" do
    assert_match(/gender F/, warnings(gender: "F").first)
    assert_match(/ability level Cat 4/, warnings(ability_level: "Cat 4").first)
    assert_match(/below minimum 35/, warnings(birth_date: Date.new(2000, 1, 1)).first)
    assert_match(/above maximum 49/, warnings(birth_date: Date.new(1970, 1, 1)).first)
  end

  test "open gender and empty ability levels accept anyone" do
    assert_empty warnings({ gender: "X", ability_level: nil }, { gender: "open", ability_levels: [] })
  end

  test "unknown birth date warns only when the category has an age range" do
    assert_match(/birth date unknown/, warnings(birth_date: nil).first)
    assert_empty warnings({ birth_date: nil }, { age_min: nil, age_max: nil })
  end
end
