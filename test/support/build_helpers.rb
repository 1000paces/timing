module BuildHelpers
  def create_event(**attrs) = Event.create!({ name: "Test CX", date: Date.new(2026, 10, 18) }.merge(attrs))

  def create_category(**attrs) = Category.create!({ name: "Cat 3 Men", gender: "M", ability_levels: ["Cat 3"] }.merge(attrs))

  def create_start_group(event:, **attrs)
    StartGroup.create!({ event:, name: "10:00", finish_rule: { "type" => "fixed_laps", "laps" => 3 } }.merge(attrs))
  end

  def create_race(event:, start_group: create_start_group(event:), category: create_category, **attrs)
    Race.create!({ event:, start_group:, category: }.merge(attrs))
  end

  def create_rider(**attrs)
    Rider.create!({ first_name: "Ada", last_name: "Rider", gender: "M", birth_date: Date.new(1985, 6, 1), ability_level: "Cat 3" }.merge(attrs))
  end

  def register(race:, bib:, rider: create_rider) = Registration.create!(race:, rider:, bib:)
end
