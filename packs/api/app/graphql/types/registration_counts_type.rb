module Types
  class RegistrationCountsType < BaseObject
    field :registered, Integer, null: false
    field :checked_in, Integer, null: false
    field :needs_bib, Integer, null: false
  end
end
