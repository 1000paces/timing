module Types
  class RaceStateEnum < BaseEnum
    value "NOT_STARTED", value: :not_started
    value "IN_PROGRESS", value: :in_progress
    value "FINISH_OPEN", value: :finish_open
  end
end
