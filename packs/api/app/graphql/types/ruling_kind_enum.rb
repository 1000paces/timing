module Types
  # Kinds recorded through recordRuling; start control, publishing, reverts and
  # suggestions have their own mutations.
  class RulingKindEnum < BaseEnum
    %w[assign_bib void_capture insert_capture flag_finish pull dnf dns dsq].each { value it.upcase, value: it }
  end
end
