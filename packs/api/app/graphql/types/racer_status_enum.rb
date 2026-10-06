module Types
  class RacerStatusEnum < BaseEnum
    value "FINISHED", value: :finished
    value "RACING", value: :racing
    value "PULLED", value: :pulled
    value "DNF", value: :dnf
    value "DNS", value: :dns
    value "DSQ", value: :dsq
  end
end
