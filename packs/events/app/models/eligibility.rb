module Eligibility
  module_function

  def warnings(rider:, category:, event:)
    warnings = []
    if category.gender != "open" && rider.gender != category.gender
      warnings << "gender #{rider.gender} does not match category gender #{category.gender}"
    end
    if category.ability_levels.present? && !category.ability_levels.include?(rider.ability_level)
      warnings << "ability level #{rider.ability_level || 'none'} is not one of #{category.ability_levels.join(', ')}"
    end
    age = event.age_of(rider.birth_date)
    if age.nil?
      warnings << "birth date unknown; category has an age range" if category.age_min || category.age_max
    else
      warnings << "age #{age} is below minimum #{category.age_min}" if category.age_min && age < category.age_min
      warnings << "age #{age} is above maximum #{category.age_max}" if category.age_max && age > category.age_max
    end
    warnings
  end
end
