module Types
  class CrossingKindEnum < BaseEnum
    value "LAP", value: :lap
    value "FINISH", value: :finish
    value "DUPLICATE", value: :duplicate, description: "Within the debounce window of the previous tap; ignored"
    value "BEFORE_START", value: :before_start
    value "AFTER_FINISH", value: :after_finish
    value "AFTER_PULL", value: :after_pull
  end
end
