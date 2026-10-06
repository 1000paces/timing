module Eligibility
  RACER_GENDER = { "men" => "M", "women" => "F" }.freeze

  module_function

  # age: the age reported for this event, used when the birth date is unknown.
  def warnings(racer:, race:, event:, age: nil)
    warnings = []
    wanted = RACER_GENDER[race.gender]
    warnings << "gender #{racer.gender} does not match #{race.name}" if wanted && racer.gender != wanted
    age = event.age_of(racer.birth_date) || age
    if age.nil?
      warnings << "age unknown; #{race.name} has an age range" if race.age_min || race.age_max
    else
      warnings << "age #{age} is below minimum #{race.age_min}" if race.age_min && age < race.age_min
      warnings << "age #{age} is above maximum #{race.age_max}" if race.age_max && age > race.age_max
    end
    warnings
  end
end
