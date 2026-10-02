module RaceSimulator
  # A ready-made CX event: one timed start group, three races 30 s apart.
  module Demo
    RACES = [
      { category: "Masters 35+ Men", gender: "M", age_min: 35, first_bib: 101 },
      { category: "Masters 50+ Men", gender: "M", age_min: 50, first_bib: 201 },
      { category: "Women Open", gender: "F", age_min: nil, first_bib: 301 }
    ].freeze
    FIRST = %w[Ana Ben Cara Dev Eli Fay Gus Hana Ivo Jun Kai Lia Max Noa Oli Pia].freeze
    LAST = %w[Abe Bose Cruz Diaz Eng Ford Gray Hale Ito Jain Kerr Lund Moss Nash Ortiz Park].freeze

    module_function

    def create!(riders_per_race: 10, name: "Demo CX")
      event = Event.create!(name:, date: Date.current, venue: "Demo Park")
      group = StartGroup.create!(event:, name: "10:00 Masters + Women",
                                 finish_rule: { "type" => "timed", "target_duration_ms" => 1_500_000 })
      RACES.each do |spec|
        category = Category.find_or_create_by!(name: spec[:category]) do |c|
          c.gender = spec[:gender]
          c.age_min = spec[:age_min]
          c.ability_levels = []
        end
        race = Race.create!(event:, start_group: group, category:)
        riders_per_race.times do |i|
          bib = spec[:first_bib] + i
          rider = Rider.create!(first_name: FIRST[bib % FIRST.size], last_name: LAST[(bib * 7) % LAST.size], gender: spec[:gender],
                                birth_date: Date.new(Date.current.year - (spec[:age_min] || 25) - 3 - (i % 5), 6, 1))
          Registration.create!(race:, rider:, bib: bib.to_s)
        end
      end
      event
    end
  end
end
