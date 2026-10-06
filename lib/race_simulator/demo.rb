module RaceSimulator
  # A ready-made CX event: three races scheduled together (they finish with the
  # leader), started in waves from the console's Start screen.
  module Demo
    RACES = [
      { age_group: "Masters 35+", gender: "men", racer_gender: "M", age_min: 35, first_bib: 101 },
      { age_group: "Masters 50+", gender: "men", racer_gender: "M", age_min: 50, first_bib: 201 },
      { name_override: "Women Open", gender: "women", racer_gender: "F", age_min: nil, first_bib: 301 }
    ].freeze
    FIRST = %w[Ana Ben Cara Dev Eli Fay Gus Hana Ivo Jun Kai Lia Max Noa Oli Pia].freeze
    LAST = %w[Abe Bose Cruz Diaz Eng Ford Gray Hale Ito Jain Kerr Lund Moss Nash Ortiz Park].freeze

    module_function

    def create!(racers_per_race: 10, name: "Demo CX")
      event = Event.create!(name:, date: Date.current, location: "Demo Park", discipline: "cyclocross")
      scheduled_at_ms = Time.current.change(hour: 10).to_i * 1000
      RACES.each do |spec|
        race = Race.create!(event:, scheduled_at_ms:, **spec.slice(:age_group, :gender, :age_min, :name_override))
        racers_per_race.times do |i|
          bib = spec[:first_bib] + i
          racer = Racer.create!(first_name: FIRST[bib % FIRST.size], last_name: LAST[(bib * 7) % LAST.size], gender: spec[:racer_gender],
                                birth_date: Date.new(Date.current.year - (spec[:age_min] || 25) - 3 - (i % 5), 6, 1))
          Registration.create!(race:, racer:, bib: bib.to_s)
        end
      end
      event
    end
  end
end
