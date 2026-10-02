module Types
  class SuggestionKindEnum < BaseEnum
    value "SUSPECTED_MISSED_CROSSING", value: :suspected_missed_crossing
    value "SUSPECTED_DUPLICATE", value: :suspected_duplicate
    value "ABOUT_TO_BE_LAPPED", value: :about_to_be_lapped
    value "UNSYNCED_CLOCK", value: :unsynced_clock
    value "UNASSIGNED_CAPTURE", value: :unassigned_capture
  end
end
